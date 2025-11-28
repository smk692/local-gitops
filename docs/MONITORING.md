# Monitoring and Observability Guide

이 문서는 Mac Mini 인프라의 모니터링 및 관찰성 스택에 대한 포괄적인 가이드입니다.

## 모니터링 스택 개요

### 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│                    Grafana Dashboard                     │
│              (Visualization & Alerting)                  │
└────────────┬──────────────────────────┬─────────────────┘
             │                          │
    ┌────────▼────────┐        ┌───────▼──────┐
    │      Loki       │        │  Prometheus  │
    │   (Logs)        │        │  (Metrics)   │
    └────────┬────────┘        └───────┬──────┘
             │                         │
    ┌────────▼────────┐        ┌───────▼──────────────────┐
    │    Promtail     │        │    Exporters:            │
    │  (Log Shipper)  │        │  - Node Exporter         │
    └─────────────────┘        │  - Kube State Metrics    │
                               │  - PostgreSQL Exporter   │
                               │  - Kafka Exporter        │
                               └──────────────────────────┘
```

### 구성 요소

1. **Grafana**: 통합 대시보드 및 시각화
2. **Loki**: 로그 수집 및 쿼리
3. **Promtail**: 로그 수집기
4. **Prometheus**: 메트릭 수집 및 저장
5. **Exporters**: 각 서비스의 메트릭 노출

## Prometheus 메트릭

### 접속 방법

```bash
# Prometheus UI 접속
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# 브라우저에서 열기
open http://localhost:9090
```

### 주요 메트릭 쿼리

#### 시스템 리소스

**CPU 사용률 (노드별)**
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**메모리 사용률 (노드별)**
```promql
100 * (1 - ((node_memory_MemAvailable_bytes) / (node_memory_MemTotal_bytes)))
```

**디스크 사용률**
```promql
100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})
```

#### Kubernetes 리소스

**Pod CPU 사용량**
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="backend"}[5m])) by (pod)
```

**Pod 메모리 사용량**
```promql
sum(container_memory_usage_bytes{namespace="backend"}) by (pod)
```

**Pod 재시작 횟수**
```promql
kube_pod_container_status_restarts_total
```

#### PostgreSQL 메트릭

**활성 연결 수**
```promql
pg_stat_activity_count
```

**데이터베이스 크기**
```promql
pg_database_size_bytes{datname="appdb"}
```

**쿼리 실행 시간 (P95)**
```promql
histogram_quantile(0.95, rate(pg_stat_statements_mean_exec_time_seconds_bucket[5m]))
```

**트랜잭션 커밋 비율**
```promql
rate(pg_stat_database_xact_commit[5m]) / (rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
```

#### Kafka 메트릭

**Consumer Lag**
```promql
kafka_consumergroup_lag
```

**메시지 처리 속도**
```promql
rate(kafka_server_brokertopicmetrics_messagesin_total[5m])
```

**브로커 상태**
```promql
kafka_server_replicamanager_underreplicatedpartitions
```

**디스크 사용률**
```promql
kafka_log_log_size
```

## Loki 로그

### 접속 방법

```bash
# Grafana에서 Loki 데이터 소스는 이미 구성되어 있습니다
kubectl port-forward -n monitoring svc/loki-grafana 3000:80

# 기본 로그인 정보
# Username: admin
# Password: kubectl get secret -n monitoring loki-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

### 로그 쿼리 예제

#### 네임스페이스별 로그

```logql
{namespace="backend"}
```

#### 에러 로그만 필터링

```logql
{namespace="backend"} |= "error" or "ERROR"
```

#### 특정 Pod 로그

```logql
{namespace="backend", pod=~"backend-service-.*"}
```

#### 5분간 에러 발생 빈도

```logql
sum(count_over_time({namespace="backend"} |= "error" [5m])) by (pod)
```

## Grafana 대시보드

### 사전 구성된 대시보드

Grafana에는 다음과 같은 대시보드를 추가할 수 있습니다:

#### 1. Kubernetes 클러스터 모니터링
- Dashboard ID: 315 (Kubernetes cluster monitoring)
- Import: Grafana → Dashboards → Import → 315

#### 2. Node Exporter Full
- Dashboard ID: 1860
- Import: Grafana → Dashboards → Import → 1860

#### 3. PostgreSQL Database
- Dashboard ID: 9628
- Import: Grafana → Dashboards → Import → 9628

#### 4. Kafka Overview
- Dashboard ID: 7589
- Import: Grafana → Dashboards → Import → 7589

### 커스텀 대시보드 생성

```bash
# Grafana 접속 후:
# 1. + 버튼 클릭 → Dashboard
# 2. Add new panel
# 3. Query 섹션에서 Prometheus 또는 Loki 선택
# 4. 위의 쿼리 예제 사용
```

## 알림 설정

### Prometheus Alertmanager

Alertmanager를 활성화하려면 `helm/prometheus-values.yaml` 수정:

```yaml
alertmanager:
  enabled: true
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: 'slack-notifications'
      group_by: ['alertname', 'cluster', 'service']
    receivers:
    - name: 'slack-notifications'
      slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#alerts'
```

### 알림 규칙 예제

`helm/prometheus-values.yaml`에 추가:

```yaml
serverFiles:
  alerting_rules.yml:
    groups:
    - name: infrastructure
      rules:
      # High CPU usage alert
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for 5 minutes"

      # High memory usage alert
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% for 5 minutes"

      # Pod crash loop
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod is crash looping"
          description: "Pod {{ $labels.pod }} is restarting frequently"

    - name: postgresql
      rules:
      # Too many connections
      - alert: PostgreSQLTooManyConnections
        expr: pg_stat_activity_count > 150
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL has too many connections"
          description: "Connection count is {{ $value }}"

    - name: kafka
      rules:
      # High consumer lag
      - alert: KafkaConsumerLag
        expr: kafka_consumergroup_lag > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Kafka consumer lag is high"
          description: "Consumer lag is {{ $value }} messages"
```

## 성능 모니터링

### 리소스 사용량 확인

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량 (전체)
kubectl top pods --all-namespaces

# 특정 네임스페이스
kubectl top pods -n backend
kubectl top pods -n infra
```

### 프로파일별 예상 사용량

#### 8GB Profile
- Kafka: ~1.5-2GB
- PostgreSQL: ~800MB
- Monitoring: ~400MB
- 예비: ~1GB

#### 16GB Profile (Default)
- Kafka: ~2.5-3GB
- PostgreSQL: ~1.5-2GB
- Monitoring: ~800MB
- 예비: ~3GB

#### 32GB Profile
- Kafka: ~5-6GB
- PostgreSQL: ~3-4GB
- Monitoring: ~1.5GB
- 예비: ~8GB

## 로그 보관 정책

### Loki 보관 기간

기본 설정: 30일

변경하려면 `helm/loki-values.yaml` 수정:

```yaml
loki:
  config:
    limits_config:
      retention_period: 720h  # 30 days
```

### Prometheus 보관 기간

기본 설정: 15일

변경하려면 `helm/prometheus-values.yaml` 수정:

```yaml
server:
  retention: "15d"
```

## 트러블슈팅

### Prometheus가 메트릭을 수집하지 않을 때

```bash
# Prometheus targets 확인
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# 브라우저: http://localhost:9090/targets

# ServiceMonitor 확인
kubectl get servicemonitor -n monitoring

# Exporter Pod 상태 확인
kubectl get pods -n monitoring
kubectl logs -n monitoring <exporter-pod-name>
```

### Loki에 로그가 표시되지 않을 때

```bash
# Promtail 상태 확인
kubectl get pods -n monitoring -l app=promtail
kubectl logs -n monitoring -l app=promtail

# Loki 상태 확인
kubectl get pods -n monitoring -l app=loki
kubectl logs -n monitoring -l app=loki
```

### Grafana 대시보드가 데이터를 표시하지 않을 때

1. **데이터 소스 연결 확인**
   ```
   Grafana → Configuration → Data Sources
   - Prometheus: http://prometheus-server.monitoring.svc.cluster.local
   - Loki: http://loki:3100
   ```

2. **쿼리 테스트**
   ```
   Grafana → Explore → 데이터 소스 선택 → 간단한 쿼리 실행
   ```

## 보안 고려사항

### 프로덕션 환경 권장사항

1. **Grafana 인증 강화**
   ```yaml
   # helm/loki-values.yaml
   grafana:
     adminPassword: "STRONG_PASSWORD"
     auth.anonymous.enabled: false
   ```

2. **Prometheus 접근 제한**
   - Network Policy로 접근 제한
   - Ingress에 Basic Auth 추가

3. **민감한 로그 필터링**
   - 비밀번호, 토큰 등 자동 마스킹
   - Promtail에서 필터 적용

## 백업 및 복구

### Prometheus 데이터 백업

```bash
# Prometheus 데이터는 PersistentVolume에 저장됨
# 스냅샷 생성
kubectl exec -n monitoring prometheus-server-0 -- \
  curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# 스냅샷 위치 확인 및 복사
kubectl exec -n monitoring prometheus-server-0 -- \
  ls -la /data/snapshots/
```

### Grafana 대시보드 백업

```bash
# Grafana API를 통한 대시보드 백출
kubectl port-forward -n monitoring svc/loki-grafana 3000:80

# 모든 대시보드 목록
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/search?query=&

# 특정 대시보드 백업
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/dashboards/uid/DASHBOARD_UID \
  > dashboard_backup.json
```

## 추가 리소스

- [Prometheus 쿼리 문법](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL 쿼리 문법](https://grafana.com/docs/loki/latest/logql/)
- [Grafana 대시보드 갤러리](https://grafana.com/grafana/dashboards/)
- [PromQL 치트시트](https://promlabs.com/promql-cheat-sheet/)
