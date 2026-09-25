<div align="center">

# ⎈ Helm, with love

### My custom Helm charts. Built for my clusters. Shared for yours. ❤️

[![Validate charts](https://github.com/swagfin/helm/actions/workflows/validate.yml/badge.svg)](https://github.com/swagfin/helm/actions/workflows/validate.yml)
![Helm 3](https://img.shields.io/badge/Helm-3-0F1689?logo=helm)
![Kubernetes](https://img.shields.io/badge/Made_for-Kubernetes-326CE5?logo=kubernetes&logoColor=white)

**A little infrastructure, a few opinions, and some love for the community.**

</div>

---

Hey, I'm [George (@swagfin)](https://github.com/swagfin). These are the custom Helm charts I've been putting together for my own Kubernetes setup. I'm putting them out here to share some love—take a look, borrow an idea, suggest an improvement, or tell me what worked for you.

They're intentionally opinionated: simple deployments, persistent storage, and settings I can understand when something needs fixing. They aren't official upstream charts or a promise that every default fits every cluster.

## 📦 Pick your chart

Every chart lives directly at the repository root. No extra `helm/` or `charts/` directory to navigate.

| Chart | What's inside |
|---|---|
| [longhorn_storage](longhorn_storage/) | Longhorn wrapper with explicit replica-storage nodes, a StorageClass, and an optional authenticated dashboard ingress. |
| [mssql](mssql/) | Single SQL Server instance, PVC data storage, a host backup folder, and tuning scripts. |
| [default-landing-zone](default-landing-zone/) | A friendly ingress fallback page with an interactive, locally bundled Kubernetes illustration. |
| [semantic-backup](semantic-backup/) | My database backup service deployment, with persistent application data and configurable upload destinations. |
| [minio](minio/) | S3-compatible object storage, currently using the Silo image with MinIO-compatible settings. |
| [redis](redis/) | A single Redis instance with persistent storage. |
| [redis-distributed](redis-distributed/) | Redis primary/replica setup with a separate PVC per pod and pods spread across nodes. |

## 🚀 Start with the landing page

```sh
git clone https://github.com/swagfin/helm.git
cd helm
helm upgrade --install landing ./default-landing-zone
```

This chart defaults to namespace `default` and ingress class `public`. It needs a matching ingress controller. Other namespace choices must already exist. The page itself loads its illustration, styles, and scripts locally.

Optional values:

```yaml
namespace: "default"
supportUrl: "https://support.example.com"
replicaCount: 1
```

```sh
helm upgrade --install landing ./default-landing-zone -f my-values.yaml
```

## 💾 Storage that stays with the application

The application storage charts default to StorageClass `longhorn`. Install Longhorn first, or select an existing compatible StorageClass where the chart exposes this setting:

```yaml
persistence:
  storageClassName: "longhorn"
  size: "5Gi"
```

- MSSQL defaults to **10Gi**. The other application storage charts here default to **5Gi** per claim.
- Application data claims use **ReadWriteOncePod**; your Kubernetes version and CSI driver must support it.
- Redis Distributed creates **one claim per pod**. Its database replication is separate from Longhorn's storage replication.
- MSSQL and Semantic Backup retain a **hostPath `/backups` mount** for exchanging backup files on the selected node.
- Existing hostPath files are **not copied automatically** into a new PVC.

For Longhorn, start with its [setup guide](longhorn_storage/README.md), [configuration reference](longhorn_storage/CONFIGURATION.md), and [plain-English storage notes](longhorn_storage/Longhorn-knowledge.md).

```sh
helm repo add longhorn https://charts.longhorn.io
helm dependency build ./longhorn_storage
helm upgrade --install longhorn ./longhorn_storage \
  --namespace longhorn-system --create-namespace -f my-values.yaml
```

Set your storage-node names and prepare their disks and host prerequisites first. The wrapper defaults to the MicroK8s kubelet path.

## 🔧 Make the defaults yours

Read the chart's `values.yaml` before installing. Keep your actual credentials and deployment values outside this public repository.

| Setting or assumption | What to check |
|---|---|
| `hostNode` | Where present, replace `k8s-master` with your node name. These workloads are pinned to that node. |
| Namespace | Most application charts create a namespace matching the Helm release name. Redis Distributed uses the fixed `redis` namespace and resource names, so install only one instance per cluster. |
| Ingress | Ingress templates use the `public` class. TLS options expect a `letsencrypt` ClusterIssuer and cert-manager. |
| Credentials | MSSQL and MinIO require you to supply their password values. Longhorn requires dashboard credentials when a domain is enabled. |
| Images | Check image access and licensing. Semantic Backup uses `ghcr.io/swagfin/semantic-backup`; this repository does not include the application source or grant registry access. |
| Redis replication | Redis Distributed uses a fixed `redis-0` primary; it does not configure Sentinel, Redis Cluster, or automatic primary promotion. |
| Upgrades | Existing StatefulSets cannot adopt changed volume claim templates in place. Plan storage changes and recovery before upgrading. |

These are source charts: install from this checkout or reference a chart directory from Argo CD. This repository does not currently publish a Helm index or OCI packages. For repeatable deployments, pin a reviewed Git commit rather than following a moving branch.

## 🤝 Share some love back

Found a rough edge? Have a clearer default or a useful improvement? [Open an issue](https://github.com/swagfin/helm/issues) or send a pull request.

Please include the chart name, Kubernetes version, and a small reproduction. Keep passwords, tokens, database connections, and private infrastructure details out of issues and examples.

Third-party software and artwork retain their own licensing; see [THIRD_PARTY.md](THIRD_PARTY.md).

<div align="center">

**Made with curiosity, Kubernetes, and a little love. — George ❤️**

</div>
