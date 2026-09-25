# Configuration reference — Longhorn 1.12.1

The local chart wraps the official chart pinned in `Chart.yaml` and `Chart.lock`.
Settings under `longhorn:` are upstream Helm values. The top-level storage
settings are **our wrapper inputs**, converted to supported Longhorn Node resources
and a Kubernetes StorageClass. They are not upstream Longhorn Helm keys.

## Storage settings you can change

Defined in `values.yaml`; release-specific overrides live in
`your private values override file`.

| Parameter | Current value | What it does |
|---|---|---|
| `storageNodes` | Empty; supply your storage nodes | Selects which servers receive managed disks. Each `name` must match a Kubernetes node name. |
| `storagePath` | `/mnt/longhorn` | Common folder for replica data. It must be on the intended persistent disk. |
| `storageNodes[].path` | Optional | Overrides the folder for one server. |
| `storageReserved` | `0` | Bytes of disk capacity excluded from scheduling, in addition to the free-space rule below. Zero does not reserve a fixed amount. |
| `storageNodes[].storageReserved` | Optional | Overrides reserved bytes for one server. An explicit `0` overrides a nonzero shared value. |
| `storageNodeTag` | `infra-storage` | Longhorn tag used to select eligible storage servers. |
| `storageDiskTag` | `infra-data` | Longhorn tag used to select eligible disks. |
| `storageClass.name` | `longhorn` | Name applications use in `storageClassName`. |
| `storageClass.numberOfReplicas` | `2` | Desired copies for each newly provisioned volume; Longhorn supports 1–20. Separate-node placement requires enough eligible servers. |

Every listed node and its managed disk are enabled for replica placement.
Unlisted nodes receive no node/disk configuration from this chart. Previously
configured nodes must be disabled and their replicas retired before removal
from the list: protected live resources are not automatically deleted or disabled.

Node and disk tags here are **Longhorn tags**, not Kubernetes pod labels. Longhorn
components may run on other Linux nodes; these selectors control replica storage.

A per-node override looks like this inside the app configuration's `overrides`:

```yaml
storageNodes:
  - name: "storage-node-01"
    path: "/mnt/longhorn"
    storageReserved: 10737418240 # Reserve 10 GiB on this disk.
  - name: "storage-node-02"
```

Do not change the path of a disk holding replicas in place. Add a new disk and
move replicas using Longhorn's disk-management procedure. Multiple directories on
the same filesystem do not provide independent disk capacity.

## Upstream Helm values

All paths below are relative to `longhorn:` in `values.yaml` and are supported by
[the official 1.12.1 values](https://github.com/longhorn/longhorn/blob/v1.12.1/chart/values.yaml).

| Parameter | Value | Purpose |
|---|---|---|
| `persistence.createStorageClass` | `false` | Stops the upstream chart from creating its StorageClass configuration; our template owns `longhorn`. |
| `preUpgradeChecker.jobEnabled` | `false` | Disables the Helm upgrade Job for Argo CD. The manager's version check remains enabled by the upstream default. |
| `csi.kubeletRootDir` | `/var/snap/microk8s/common/var/lib/kubelet` | Location used to register the storage driver with MicroK8s. Change only if the actual kubelet root differs. |
| `global.tolerations` | Control-plane and master `NoSchedule` taints, operator `Exists` | Allows Helm-managed Longhorn components onto those nodes. It does not force them there. |
| `ingress.enabled` | `false` | Disables the upstream ingress; the wrapper uses `domain` to create its authenticated ingress. |

`persistence.defaultClass` was removed from our overrides because
`createStorageClass: false` makes it unused. The custom StorageClass explicitly
sets its own default-class annotation to `false`.

## Longhorn default settings

These paths are relative to `longhorn.defaultSettings`. The chart writes them into
Longhorn's default-settings ConfigMap.

| Parameter | Value | Purpose |
|---|---|---|
| `createDefaultDiskLabeledNodes` | `true` | Only automatically creates disks on Kubernetes nodes labeled `node.longhorn.io/create-default-disk=true`. We add no such labels; disks are declared explicitly. Leave that label absent for this fresh installation. |
| `defaultDataPath` | `/mnt/longhorn` | Fallback path for automatically created disks. Explicit node disks use `storagePath` or the per-node `path`. |
| `defaultReplicaCount` | `2` | Default copy count for volumes created through the UI. PVC volumes use the StorageClass count instead. |
| `v1DataEngine` | `true` | Enables the filesystem/iSCSI storage engine used here. |
| `v2DataEngine` | `false` | Disables the alternative V2 engine. |
| `replicaSoftAntiAffinity` | `false` | Does not place healthy copies of the same volume together on one node. |
| `replicaZoneSoftAntiAffinity` | `true` | Allows multiple copies in one zone when needed, still on different nodes. |
| `storageMinimalAvailablePercentage` | `25` | Stops scheduling additional replicas when the disk fails the minimum-free-space check. This is not a filesystem quota and does not stop existing applications writing. |
| `storageOverProvisioningPercentage` | `100` | Limits scheduled replica capacity to 100% of usable disk capacity, with reserved space accounted for. |
| `allowEmptyNodeSelectorVolume` | `false` | Volumes without node selectors cannot use tagged nodes. UI-created volumes must select `infra-storage` to use these nodes. |
| `allowEmptyDiskSelectorVolume` | `false` | Volumes without disk selectors cannot use tagged disks. UI-created volumes must select `infra-data` to use these disks. |
| `deletingConfirmationFlag` | `false` | Keeps Longhorn's uninstall confirmation disabled. It is not general protection against direct Kubernetes deletion. |
| `taintToleration` | Control-plane/master `NoSchedule` tolerations | Allows Longhorn-created instance managers and CSI components onto these nodes. Separate from Helm-managed component tolerations above. |

The scalar `defaultReplicaCount: 2` is supported in 1.12.1 even though the setting
also accepts engine-specific values. Only V1 is enabled here.

## Generated StorageClass

Defined in `templates/storageclass.yaml`. These are Kubernetes fields or
[Longhorn CSI parameters](https://longhorn.io/docs/1.12.1/references/storage-class-parameters/),
not arbitrary Helm properties.

| Field | Value | Meaning |
|---|---|---|
| `provisioner` | `driver.longhorn.io` | Asks Longhorn to create the volume. |
| Default-class annotation | `false` | Applications must explicitly request `storageClassName: longhorn`. |
| `allowVolumeExpansion` | `true` | Allows a PVC to request more space later. |
| `reclaimPolicy` | `Retain` | Deleting a PVC leaves its PV/data for manual cleanup or recovery. |
| `volumeBindingMode` | `Immediate` | Starts provisioning when the PVC is created. |
| `parameters.numberOfReplicas` | `"2"` | Desired copies, from `storageClass.numberOfReplicas`. |
| `parameters.fsType` | `ext4` | Filesystem created inside the application volume. |
| `parameters.dataEngine` | `v1` | Uses the enabled V1 engine. |
| `parameters.dataLocality` | `disabled` | Does not require a copy on the application node; storage tags determine eligible locations. |
| `parameters.nodeSelector` | `infra-storage` | Selects nodes with our Longhorn node tag. |
| `parameters.diskSelector` | `infra-data` | Selects disks with our Longhorn disk tag. |
| `parameters.replicaSoftAntiAffinity` | `disabled` | Requires separate-node placement for healthy copies. This uses an enum, unlike the global boolean setting. |
| `parameters.replicaZoneSoftAntiAffinity` | `enabled` | Permits copies in the same zone on separate nodes. |

StorageClass parameters affect **new volumes**. Kubernetes does not allow changing
many StorageClass fields in place; create a differently named class for a new
policy. Existing volumes retain their own settings.

## Generated Longhorn nodes

`templates/storage-nodes.yaml` creates `longhorn.io/v1beta2` Node resources in
`longhorn-system`. It does not modify the Kubernetes Node objects.

| Field | Meaning |
|---|---|
| `metadata.name` and `spec.name` | Both identify the selected Kubernetes node. Longhorn's update validator requires a nonempty `spec.name`. |
| `spec.allowScheduling` | Always `true` for listed storage nodes. |
| `spec.tags` | Adds the configured storage-node tag. |
| `spec.disks.infra-data` | Stable name of the managed disk entry. |
| Disk `diskType: filesystem` | Uses a directory on a mounted filesystem, compatible with V1. |
| Disk `path` | The shared or per-node storage directory. |
| Disk `allowScheduling` | Always `true` for the managed disk on a listed node. |
| Disk `storageReserved` | Reserved bytes as configured above. |
| Disk `tags` | Adds the configured storage-disk tag. |

## Argo CD settings

These are deployment controls, not Longhorn parameters:

| Setting | Purpose |
|---|---|
| `CreateNamespace=true` | Creates `longhorn-system` when needed. |
| `ServerSideApply=true` | Applies resources including large upstream CRDs using the server-side API. |
| Node `sync-wave: "1"` | Applies node configuration after upstream resources are ready. |
| Node/StorageClass `Prune=false,Delete=false` | Prevents Argo from automatically pruning/deleting those resources. Retiring a node needs a deliberate operational procedure. |

Keep sync pruning off for routine installation. These controls cannot stop an
administrator from explicitly deleting resources or choosing cascading deletion.

Changing an existing StorageClass replica-count parameter requires recreating
its definition or using a new class name; existing volumes retain their settings.

## Version audit

Checked against the downloaded **1.12.1 chart**, its Node CRD schema, and the
versioned [CSI parser](https://github.com/longhorn/longhorn-manager/blob/v1.12.1/csi/util.go),
[settings definitions](https://github.com/longhorn/longhorn-manager/blob/v1.12.1/types/setting.go),
and [node validator](https://github.com/longhorn/longhorn-manager/blob/v1.12.1/webhook/resources/node/validator.go).
All retained upstream keys and StorageClass parameters are supported. Wrapper
inputs and Argo annotations are intentionally separate from Longhorn's settings.
Live installation and volume attachment still require cluster validation.

## Dashboard ingress and credentials

These are wrapper values, alongside `storageClass` (not under `longhorn`):

| Parameter | Default | Purpose |
|---|---|---|
| `domain` | Empty | Nonempty hostname creates the dashboard ingress and auth Secret. |
| `useLetsEncrypt` | `false` | When true, requests a certificate from ClusterIssuer `letsencrypt`, adds TLS, and redirects HTTP to HTTPS. Requires cert-manager. Otherwise HTTPS must be arranged separately. |
| `basicAuth.username` | `admin` | Login name, stored directly in values. Colons and newlines are rejected. |
| `basicAuth.password` | Empty | Login password; required when domain is set, at most 72 bytes for bcrypt. |

The ingress template fixes `ingressClassName` to `public`; that class must support
ingress-nginx annotations. It is not configurable through values.

The Secret is named `<release>-ui-auth` in the release namespace and contains a
bcrypt `htpasswd` entry under `data.auth`. The ingress routes to
`longhorn-frontend:80`. Keep upstream `longhorn.ingress.enabled` disabled to avoid
a separate route without the wrapper's authentication.

For an Argo CD deployment, configure `ignoreDifferences` for `/data/auth` on
`longhorn-system/longhorn-ui-auth` in your Application. It avoids salt-only drift, but also hides manual changes to that
field. A full manual sync still applies the generated Secret and changed
credentials. Do not enable `RespectIgnoreDifferences=true` or selective
out-of-sync-only syncing for credential rotation. Update the ignore rule if the
release name or namespace changes.
