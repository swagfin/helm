# Understanding PVCs and Longhorn in plain English

This guide explains the storage concepts used in this repository. The Longhorn
details refer to **Longhorn 1.12.1 with the V1 engine**, which our chart selects.
Examples are for learning; adding this document does not create any storage or
migrate an application.

## 1. Start with what you already know: hostPath

A volume is a place where your application can read and save files.

With `hostPath`, you tell Kubernetes:

> Take this folder on the server and make it available inside my application.

For example, these entries inside a pod's configuration connect a server folder
to an application folder:

```yaml
volumeMounts:
  - name: "app-storage"
    mountPath: "/app/Data"

volumes:
  - name: "app-storage"
    hostPath:
      path: "/mnt/my-app"
```

`volumeMounts` belongs under the container; `volumes` belongs under the pod spec.
This is a fragment, not a complete manifest.

When the application writes `/app/Data/invoice.pdf`, that file is stored as
`/mnt/my-app/invoice.pdf` on the server running the pod.

If the application moves to another server, the same folder name on that server
does **not** automatically contain the same files. Restarting on the original
server may reuse its files, but losing that server's disk can lose the data.

## 2. What changes with Longhorn?

With Longhorn, you say:

> Give my application 10 GiB of storage. Manage where it lives and keep copies
> on my selected servers.

The application still reads and writes an ordinary folder such as `/app/Data`.
Longhorn manages the storage behind it.

```text
hostPath:
Application → folder on one server

Longhorn:
Application → managed volume → copies on selected storage servers
```

Our enabled replica-storage servers are:

- `storage-node-01`
- `storage-node-02`

Longhorn stores replica data under `/mnt/longhorn` on those servers. Your
application does not mount that host directory directly. Let Longhorn manage
the files inside it.

The copies exist **before** a failure. If the application server fails, a
replacement pod can use the surviving data after storage handover. Failure
detection, restarting the application, and attaching its volume take time.
This is not a promise of zero downtime.

The application must also be allowed to run elsewhere. A hard requirement to
run on one particular hostname can prevent recovery even when the data is safe.

## 3. StorageClass, PVC, PV, and volume

| Name | Plain-English meaning | Who normally creates it? |
|---|---|---|
| StorageClass | A storage plan describing how new storage should be provided | An administrator or Helm chart |
| PVC — PersistentVolumeClaim | An application's request for storage | You, usually through the application's chart |
| PV — PersistentVolume | Kubernetes' record of the storage assigned to that request | Kubernetes and the storage driver, automatically |
| Longhorn volume | The actual managed storage behind the PV | Longhorn, automatically |
| Pod volume | The connection between the pod and its storage | Declared in the application manifest |
| Volume mount | The folder inside a container where that storage appears | Declared in the container configuration |

For our normal workflow, **create the PVC and let the system create the PV and
Longhorn volume**. You do not manually create all three.

```text
PVC: “I need 10 GiB using the longhorn storage plan.”
                       ↓
StorageClass: “Use Longhorn with two copies on eligible servers.”
                       ↓
Kubernetes + Longhorn create the PV and underlying volume.
                       ↓
Your application mounts the PVC at /app/Data.
```

Our StorageClass is named `longhorn`. It is not the cluster default, so the PVC
must explicitly specify `storageClassName: longhorn`.

## 4. Create a PVC and let an application use it

Save this complete example as `app-storage.yaml`:

```yaml
apiVersion: "v1"
kind: "Namespace"
metadata:
  name: "my-app"
---
apiVersion: "v1"
kind: "PersistentVolumeClaim"
metadata:
  name: "my-app-data"
  namespace: "my-app"
spec:
  accessModes:
    - "ReadWriteOnce"
  storageClassName: "longhorn"
  resources:
    requests:
      storage: "10Gi"
```

It means: “Request 10 GiB named `my-app-data` in `my-app`, using Longhorn, with
read/write access from one server at a time.”

From a machine configured to access the cluster:

```sh
kubectl apply -f app-storage.yaml
kubectl -n my-app get pvc my-app-data
kubectl get pv
```

The PVC should become **Bound**, meaning storage has been assigned. A `Pending`
PVC is still waiting; inspect it with:

```sh
kubectl -n my-app describe pvc my-app-data
```

To use the storage, merge this fragment into your existing Deployment or
StatefulSet under `spec.template.spec`. Keep your application's real image,
ports, environment variables, and other settings:

```yaml
containers:
  - name: "your-existing-container"
    image: "your-existing-image"
    volumeMounts:
      - name: "app-storage"
        mountPath: "/app/Data"
volumes:
  - name: "app-storage"
    persistentVolumeClaim:
      claimName: "my-app-data"
```

The pod and PVC must be in the **same namespace**. Choose the mount path where
your application actually writes data. This fragment is not a complete file to
apply on its own.

The main difference from hostPath is this:

```yaml
# Previously:
hostPath:
  path: "/mnt/my-app"

# With managed storage:
persistentVolumeClaim:
  claimName: "my-app-data"
```

Changing that reference does not copy the old files. Migrating an existing
application needs a separate, consistent data-transfer procedure.

## 5. Access modes: who can use the storage at the same time?

A **node** is a server. A **pod** is a running application instance, possibly
containing several containers.

Access modes describe how storage can be mounted. They do not describe how many
copies Longhorn keeps, and they do not replace application file permissions or
coordination between writers.

| Mode | Meaning | Longhorn 1.12.1 support | Example |
|---|---|---|---|
| `ReadWriteOnce` — RWO | Read/write from one node at a time | Yes | A single application or database instance |
| `ReadWriteOncePod` — RWOP | Exclusive access by one pod across the cluster | Yes, with compatible Kubernetes/CSI components | A database needing exclusive ownership of its files |
| `ReadWriteMany` — RWX | Multiple nodes can read and write concurrently | Yes | Several API instances sharing uploads |
| `ReadOnlyMany` — ROX | Multiple nodes can mount for reading only | Not directly | Shared reference files; use RWX with read-only mounts for Longhorn |

### RWO: one server at a time

```yaml
accessModes:
  - "ReadWriteOnce"
```

For example, `mssql-01` uses the volume from its current server. Longhorn keeps
copies on the other storage servers, but those copies are not additional writable
mounts for other database instances.

“Once” means **one node**, not one pod. Multiple pods on that same node may use
the volume. It also does not mean “this server forever”: after detachment, the
volume can be attached to another server.

### RWOP: one pod at a time

```yaml
accessModes:
  - "ReadWriteOncePod"
```

Suppose a second database pod accidentally starts. RWOP prevents that second
pod from using the same claim while the first owns it, even on the same server.
It provides stronger exclusivity than RWO.

This is useful for a single MSSQL or MariaDB instance. Multiple containers inside
the one pod can still share its storage. Updates need to release the old pod's
volume before the replacement can use it.

### RWX: several servers share a folder

```yaml
accessModes:
  - "ReadWriteMany"
```

Imagine three API instances on different servers. A customer uploads a photo
through API A; APIs B and C need to read that same photo:

```text
API on server A ─┐
API on server B ─┼── Shared uploads volume
API on server C ─┘
```

Other examples are document folders, report-generation workers, and file
processing services. Longhorn provides this shared filesystem through an NFS
service that it manages.

RWX does not prevent two applications from overwriting the same file. The
application needs appropriate coordination. It does **not** make it safe for
independent database servers to open the same database files. Database clustering
needs the database's own supported replication/coordination design.

### ROX: shared reading

ROX is useful for published datasets, reference documents, or model files, but
Longhorn 1.12.1 does not support it directly.

Instead, request RWX and make each reader's mount read-only:

```yaml
volumeMounts:
  - name: "shared-files"
    mountPath: "/app/reference"
    readOnly: true
```

This prevents writing through that mount. A different pod with a writable mount
could still update the same files. NFS is still required.

Normally choose one access mode per PVC. An application can have multiple PVCs
with different purposes, such as exclusive database storage and shared documents.

## 6. Access modes and rolling updates

A Deployment may create a replacement pod before stopping the old one. With
RWOP, that can create a circular wait:

1. The old pod owns the volume.
2. The replacement starts but cannot use that volume.
3. The replacement cannot become ready.
4. The Deployment waits for it to be ready before stopping the old pod.

The volume is behaving correctly; the rollout strategy is unsuitable for
exclusive storage access.

For a single-instance Deployment, a straightforward strategy is:

```yaml
spec:
  replicas: 1
  strategy:
    type: "Recreate"
```

When editing an existing Deployment, remove any `strategy.rollingUpdate` settings
as well. `Recreate` stops old pods before creating replacements during an update,
so plan for downtime while the application shuts down and starts again.

A StatefulSet normally deletes and recreates each instance in turn during a
rolling update. It does not create a second copy of the same instance first.
Our MSSQL charts use StatefulSets.

A stuck terminating pod or delayed storage detach can still delay recovery. RWOP
provides exclusivity, not guaranteed immediate handover. RWO can also encounter
attachment delays if a replacement tries to mount from a different server.

## 7. What needs installing on the servers?

For **our V1 engine configuration**:

| Mode | Needs iSCSI support? | Needs NFS for application access? |
|---|---|---|
| RWO | Yes | No |
| RWOP | Yes | No |
| RWX | Yes, for the underlying V1 storage | Yes, on every node mounting the shared filesystem |
| RWX with read-only mounts | Yes, for the underlying V1 storage | Yes |

NFS may separately be required if you choose an NFS backup destination, even
when applications use RWO or RWOP.

On Ubuntu/Debian, the relevant host components are:

| Component | Purpose |
|---|---|
| `open-iscsi` | Provides the storage connection tools, including `iscsiadm`. |
| Running `iscsid` service | Handles iSCSI connections. |
| `iscsi_tcp` kernel module | Enables iSCSI over TCP. |
| `nfs-common` | Provides the NFS client needed for shared RWX mounts; RWX requires NFSv4.1 support. |
| Tools including `bash`, `curl`, `findmnt`, `grep`, `awk`, `blkid`, and `lsblk` | Allow Longhorn to inspect and manage host storage. |

The cluster also needs mount propagation and permission for Longhorn's privileged
components. Replica storage for V1 uses an ext4 or XFS host filesystem. Prepare
storage servers and any other servers that may run applications consuming volumes.
Installing the Helm chart does not itself install these host packages.

Longhorn 1.12.1 requires Kubernetes 1.25 or newer. RWOP became stable in Kubernetes
1.29; use 1.29+ as the straightforward baseline for that mode. Earlier versions
have feature-stage considerations.

RWOP also needs these minimum CSI component versions:

- `csi-provisioner`: 3.0.0+
- `csi-attacher`: 3.3.0+
- `csi-resizer`: 1.3.0+

These run as Kubernetes components supplied through Longhorn, not host packages
installed with `apt`. The pinned chart's default versions exceed these minimums.

At the time of this review, Longhorn's documentation flags `open-iscsi 2.1.12` as
incompatible and recommends versions up to 2.1.11 or from 2.1.13 onward. Check the
current upstream notice when preparing hosts.

## 8. Storage copies do not mean application instances

These are independent settings:

| Setting | Controls |
|---|---|
| Application `replicas` | How many application pods run |
| Longhorn `numberOfReplicas` | How many copies of a volume's data Longhorn maintains |
| PVC `accessModes` | How applications may mount the volume concurrently |

One database pod can use RWOP while Longhorn keeps two copies of its data.
You do not need RWX just because data is replicated across servers.

Our storage rules request one healthy copy per selected node. If one node fails,
the volume may continue with fewer healthy copies; the missing copy cannot be
restored on a second available node until the failed node returns or another eligible
node is added. Storage recovery also depends on Kubernetes and workload recovery.

Two copies of 10 GiB of written data need roughly 20 GiB in total, plus space
for snapshots and overhead. Replication is not a backup: unwanted changes and
deletions can be replicated too.

## 9. Growing, deleting, and keeping data

Our StorageClass allows expansion. Increase the PVC's requested size and apply
the change. Shrinking is not supported.

Deleting or replacing an application pod does not normally delete its separate
PVC. A replacement can reuse that claim.

Our StorageClass uses **Retain**. Deleting a PVC leaves its PV and Longhorn data
for deliberate cleanup or recovery. An administrator must identify the correct
volume before deleting it. A new PVC with the same name does not automatically
reconnect to the retained data.

Changing a StorageClass policy does not rewrite the settings of existing volumes.
Many StorageClass fields also cannot be changed in place. Use a new class for a
new policy and Longhorn's controls for supported existing-volume changes.

## 10. Git, the dashboard, and our current scope

Our node names are configured in `your private values override file`. Shared
defaults are in `values.yaml`. The templates create Longhorn node/disk entries
and the `longhorn` StorageClass.

The UI is useful for inspecting disks, replica health, and volumes. Keep changes
to Git-managed fields in Git: a future sync or Helm upgrade can overwrite manual
edits to those same fields. Some volume operations are managed through the UI.

Our node/disk selectors use **Longhorn storage tags**. They are different from
Kubernetes pod selectors, which control where application pods run. UI-created
volumes must select node tag `infra-storage` and disk tag `infra-data` to use our
tagged storage. PVCs using our StorageClass receive those selectors automatically.

Installing Longhorn does not migrate existing hostPath applications. They remain
unchanged until we deliberately provision PVCs, migrate data, and update their
volume mounts.

See [README](README.md) for the deployment workflow and
[Configuration reference](CONFIGURATION.md) for every configured parameter.

## Official references

- [Kubernetes volumes and access modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes RWOP requirements](https://kubernetes.io/docs/tasks/administer-cluster/change-pv-access-mode-readwriteoncepod/)
- [Deployment update strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
- [StatefulSet updates](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#rolling-updates)
- [Longhorn 1.12.1 access modes and volume creation](https://longhorn.io/docs/1.12.1/nodes-and-volumes/volumes/create-volumes/)
- [Longhorn shared RWX volumes](https://longhorn.io/docs/1.12.1/nodes-and-volumes/volumes/rwx-volumes/)
- [Longhorn host requirements](https://longhorn.io/docs/1.12.1/deploy/install/)
- [Longhorn node failure recovery](https://longhorn.io/docs/1.12.1/high-availability/node-failure/)

## Choosing where new replicas may be stored

List your storage servers under `storageNodes`. The chart enables replica
placement on each listed node and its managed disk. Application pods can still
use this storage from other nodes.

Before removing a previously configured node, disable its storage scheduling and
safely retire any existing replicas through Longhorn. Removing its list entry
alone does not change the protected live resource.
