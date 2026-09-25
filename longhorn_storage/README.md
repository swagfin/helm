# Longhorn storage

New to PVCs? Read [Understanding PVCs and Longhorn in plain English](Longhorn-knowledge.md)
for hostPath comparisons, access modes, server requirements, and examples.

This chart installs **Longhorn 1.12.1**. Longhorn keeps copies of a volume on
separate servers so its data can survive a server failure. Recovery can involve
application downtime. Replication does not replace backups.

Example setup (supply your actual node names):

| Item | Configuration |
|---|---|
| Storage servers | `storage-node-01`, `storage-node-02` |
| Data folder on each server | `/mnt/longhorn` |
| StorageClass (storage plan name) | `longhorn` |
| Copies per new volume | 2, on separate servers |
| Automatically used by existing apps? | No |
| What happens when a storage request is deleted? | Data is retained for deliberate cleanup |

Existing hostPath folders are not copied or migrated. The chart creates no
application volumes until someone requests one.

## Where to change settings

- **Server names:** `your private values override file`, under `storageNodes`.
- **Folder and number of copies:** `longhorn_storage/values.yaml`, under
  `storagePath` and `storageClass.numberOfReplicas`.
- **All other parameters:** see [Configuration reference](CONFIGURATION.md).

Keep changes to these managed settings in Git. UI changes to the same fields can
be overwritten by the next deployment. Removing a server from Git does not safely
move or delete its existing data; it must first be retired through Longhorn.

## Install and open the dashboard

### Install iSCSI on the servers first

Our Longhorn V1 volumes use **iSCSI** to present network-backed storage to an
application's server as a disk. `open-iscsi` provides the connection tools
(`iscsiadm`); the `iscsid` service handles those connections. This is required for
RWO and RWOP volumes. NFS is not required for those application mounts; shared
RWX mounts additionally need an NFS client such as `nfs-common` on Ubuntu.

Run the following on each Ubuntu/Debian **host**, not inside a pod. Prepare every
node running a Longhorn manager and any node that will consume these volumes,
not only the two selected replica-storage nodes.

First, check the version your package repository will install:

```sh
sudo apt-get update
apt-cache policy open-iscsi
```

> **Version warning:** Longhorn flags `open-iscsi 2.1.12` as incompatible because
> it can cause volume attachment failures. Do not install that version. The
> upstream guidance is to use versions up to `2.1.11` or from `2.1.13` onward.
> Check the `Candidate:` entry before continuing: an unversioned install uses
> your repository's candidate and does not automatically exclude `2.1.12`.
> See the [official compatibility notice](https://longhorn.io/docs/1.12.1/deploy/install/#install-open-iscsi).

If the candidate is compatible, install without pinning a version:

```sh
sudo apt-get install -y open-iscsi
sudo modprobe iscsi_tcp
sudo systemctl enable --now iscsid
```

Verify the installed version and running service:

```sh
iscsiadm --version
systemctl is-active iscsid
```

The service should report `active`. A manager failing with
`iscsiadm: No such file or directory` is missing the host tool. Kubernetes will
retry the pod after installation; allow time for its restart backoff.

### Prepare the storage folder on the two selected servers

Run these steps directly on each storage host:

- `storage-node-01`
- `storage-node-02`

First, check which disk backs `/mnt` and how much space is available:

```sh
findmnt -T /mnt
df -hT /mnt
ls -ld /mnt/longhorn
```

If `findmnt` shows `/` as the mount target, `/mnt` shares the system disk with
the OS and existing applications; it is not a separate storage disk. Confirm
this is where you intend to store replicas. If using a separate disk, mount it
persistently at the intended location before creating the folder.

Create the directory if it is missing:

```sh
sudo mkdir -p /mnt/longhorn
ls -ld /mnt/longhorn
```

This creates a folder only; it does not format a disk or reserve space. The chart
declares the storage path but does not create this host directory for you.

If Longhorn is already running, it should detect the folder automatically. Refresh
the dashboard and expand the selected nodes: their disks should show actual
capacity and become **Ready/Schedulable**. A missing folder can cause the disk to
show **Unschedulable**, **0 Bi**, and “disk is not ready.” If it remains unready,
inspect the disk condition for the underlying error instead of reinstalling.

The displayed disk size is the filesystem's total capacity, not all free space.
Existing OS/application files also count toward used space. Our 25% minimum-free-
space setting limits additional replica scheduling; creating this folder does
not give Longhorn an empty or dedicated disk.

### Deploy Longhorn

Before the first installation, an administrator must confirm the host packages
(`open-iscsi`, plus `nfs-common` when using RWX or NFS backups on Ubuntu), running
`iscsid`, and available disk space.
Prepare `/mnt/longhorn` as described above. This chart does not format disks or
install host packages. Volume-consuming
servers also need Longhorn prerequisites. See the
[official host requirements](https://longhorn.io/docs/1.12.1/deploy/install/).

Install with your own values file using the commands below.
The default kubelet path targets MicroK8s; override it for other distributions. This is for a fresh installation;
an existing Longhorn deployment needs an adoption/upgrade review first.

For local chart validation:

```sh
helm repo add longhorn https://charts.longhorn.io
helm dependency build longhorn_storage
helm lint longhorn_storage
helm upgrade --install longhorn ./longhorn_storage --namespace longhorn-system --create-namespace -f my-values.yaml
```

Open the dashboard from a machine with cluster access:

```sh
kubectl -n longhorn-system port-forward service/longhorn-frontend 8080:80
```

Visit **http://localhost:8080**. Check that both storage servers and their
disks are ready before creating volumes. The dashboard is not exposed publicly while `domain` is empty.

## Open the dashboard using a domain

Set these properties in `values.yaml` and manually sync the application:

```yaml
domain: "longhorn.example.com"
useLetsEncrypt: true
basicAuth:
  username: "admin"
  password: "<choose-a-strong-password>"
```

Point the domain's DNS at your ingress endpoint. `useLetsEncrypt: true` requires
cert-manager and the existing `letsencrypt` ClusterIssuer. The `public` ingress
class must be handled by ingress-nginx for the authentication annotations to work.

The browser will ask for the username and password in `basicAuth.username` and
`basicAuth.password`. Supply these credentials in a private values file; the chart ships with a blank password. Helm generates a bcrypt password entry and creates the Kubernetes
Secret automatically; no manual `htpasswd` command or Secret creation is needed.

A blank `domain` creates neither the ingress nor its authentication Secret.
Keep `longhorn.ingress.enabled: false`; our wrapper creates the authenticated
route to `longhorn-frontend` instead. If `useLetsEncrypt` is false, the wrapper
adds no TLS configuration or HTTPS redirect; arrange HTTPS separately before
using the login. Basic authentication protects this ingress, not local
port-forwarding or direct service access.

Change credentials in `values.yaml`, then manually sync the full application
including the Secret. If you use Argo CD, configure it to ignore `/data/auth` differences on this one Secret
because bcrypt produces a fresh salt each time; this also hides manual edits to
that field. Do not add `RespectIgnoreDifferences=true` or sync only out-of-sync
resources when rotating credentials, because the Secret must be applied.

## Create storage for an application

You normally create a **PVC** (PersistentVolumeClaim): a request for storage.
Kubernetes and Longhorn automatically create the **PV** (PersistentVolume) and the
underlying Longhorn volume. You do not need to create all three manually.

Save this as `app-storage.yaml`. It requests **10 GiB** in an example namespace:

```yaml
apiVersion: "v1"
kind: "Namespace"
metadata:
  name: "my-app"
---
apiVersion: "v1"
kind: "PersistentVolumeClaim"
metadata:
  name: "app-data"
  namespace: "my-app"
spec:
  accessModes:
    - "ReadWriteOnce"
  storageClassName: "longhorn"
  resources:
    requests:
      storage: "10Gi"
```

Apply and check it:

```sh
kubectl apply -f app-storage.yaml
kubectl -n my-app get pvc app-data
kubectl get pv
```

The PVC should become **Bound**. The volume appears in Longhorn's dashboard.
Two copies of 10 GiB of written data use roughly 20 GiB in total, plus overhead
and snapshots. If one server is unavailable, two healthy copies cannot be
restored until it returns or another eligible server is added.

## Let an application use the volume

The application must be in the **same namespace** as the PVC. Add these entries to
its Deployment or StatefulSet, preserving its existing containers and settings:

```yaml
# Within spec.template.spec:
containers:
  - name: "your-existing-container"
    image: "your-existing-image"
    volumeMounts:
      - name: "app-storage"
        mountPath: "/data"
volumes:
  - name: "app-storage"
    persistentVolumeClaim:
      claimName: "app-data"
```

This is a fragment to merge into your application's manifest, not a complete file
to apply. Choose the mount path where that application writes its data. Files
written there use the Longhorn volume. This does not migrate old hostPath files.

`ReadWriteOnce` permits a read/write mount on one node at a time. Use this example
for a single application instance; do not point independent database instances
at the same claim. Existing hostname pinning can also prevent an application from
moving to another server after a failure.

## Expanding or deleting storage

To grow storage, change `10Gi` to a larger size and apply the PVC again. Shrinking
is not supported. Changing the StorageClass replica count affects new volumes;
use Longhorn's volume controls for an existing volume.

Deleting the PVC **does not delete its retained data**. An administrator must
identify and remove the released PV and its Longhorn volume when they are no
longer needed. A new PVC with the same name does not automatically recover that
old data. Avoid deleting the `longhorn-system` namespace.

## Validation scope

Configuration was checked against the pinned 1.12.1 chart, Node schema, and
Longhorn settings/CSI source. Local rendering does not verify live host packages,
disk capacity, or successful volume attachment; those require cluster access.
