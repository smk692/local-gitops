# Local GitOps Repository

친구(Chingu)가 관리하는 로컬 Kubernetes 클러스터용 GitOps 저장소입니다.

## 구조

```
local-gitops/
├── apps/                    # ArgoCD Application 정의
│   ├── observability/       # 모니터링 스택 (Grafana, Loki, Prometheus, Tempo, Alloy)
│   ├── infrastructure/      # 인프라 (Traefik, Redpanda, cert-manager)
│   └── applications/        # 애플리케이션 (n8n 등)
│
├── helm-values/             # Helm values 파일
│   ├── grafana.yaml
│   ├── loki.yaml
│   └── ...
│
├── base/                    # 공통 리소스 (네임스페이스, RBAC 등)
│   └── namespaces.yaml
│
└── app-of-apps.yaml         # 루트 Application (모든 앱 관리)
```

## 사용법

### 새 앱 추가
1. `apps/카테고리/앱이름.yaml` 생성
2. 필요시 `helm-values/앱이름.yaml` 생성
3. Git push → ArgoCD 자동 감지

### 앱 수정
1. 해당 yaml 파일 수정
2. Git push → ArgoCD 자동 sync

## 현재 배포된 앱

| 앱 | 네임스페이스 | 상태 |
|---|---|---|
| Grafana | observability | ✅ |
| Loki | observability | ✅ |
| Prometheus | observability | ✅ |
| Tempo | observability | ✅ |
| Alloy | observability | ✅ |
| Traefik | infrastructure | ✅ |
| Redpanda | infrastructure | ✅ |
| n8n | applications | ⚠️ |

## ArgoCD 접속

```bash
# 포트포워딩
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 초기 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
