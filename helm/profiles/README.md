# Resource Profiles for Different Mac Mini Configurations

리소스 프로파일을 사용하여 맥 미니 사양에 맞게 최적화된 설정을 적용할 수 있습니다.

## 프로파일 종류

### 8GB Profile (8gb-profile.yaml)
- **대상**: M1 Mac Mini 8GB RAM
- **특징**: 최소 리소스 사용, 단일 복제본
- **권장**: 개발/테스트 환경

**예상 리소스 사용**:
- Kafka: 2GB
- PostgreSQL: 1GB
- Monitoring: 0.5GB
- Backend/Frontend: 1GB
- 시스템 예약: 2GB
- 여유: 1.5GB

### 16GB Profile (16gb-profile.yaml) - DEFAULT
- **대상**: M1/M2 Mac Mini 16GB RAM
- **특징**: 균형잡힌 리소스, 표준 복제본
- **권장**: 소규모 프로덕션

**예상 리소스 사용**:
- Kafka: 3GB
- PostgreSQL: 2GB
- Monitoring: 1GB
- Backend/Frontend: 2GB
- 시스템 예약: 3GB
- 여유: 5GB

### 32GB Profile (32gb-profile.yaml)
- **대상**: M2 Pro/Max Mac Mini 32GB RAM
- **특징**: 고성능 설정, 다중 복제본
- **권장**: 중규모 프로덕션

**예상 리소스 사용**:
- Kafka: 6GB
- PostgreSQL: 4GB
- Monitoring: 2GB
- Backend/Frontend: 4GB
- 시스템 예약: 4GB
- 여유: 12GB

## 사용 방법

### 배포 시 프로파일 적용

```bash
# 8GB 프로파일 사용
helm upgrade --install kafka bitnami/kafka \
  --namespace infra \
  --values helm/kafka-values.yaml \
  --values helm/profiles/8gb-profile.yaml

# 16GB 프로파일 사용 (기본)
helm upgrade --install kafka bitnami/kafka \
  --namespace infra \
  --values helm/kafka-values.yaml \
  --values helm/profiles/16gb-profile.yaml

# 32GB 프로파일 사용
helm upgrade --install kafka bitnami/kafka \
  --namespace infra \
  --values helm/kafka-values.yaml \
  --values helm/profiles/32gb-profile.yaml
```

### 배포 스크립트에서 프로파일 선택

`scripts/deploy-all.sh` 실행 시 환경 변수로 프로파일 지정:

```bash
export PROFILE=8gb
# 또는
export PROFILE=16gb
# 또는
export PROFILE=32gb

./deploy-all.sh
```

## 프로파일 커스터마이징

프로파일 파일을 복사하여 자신만의 프로파일 생성:

```bash
cp helm/profiles/16gb-profile.yaml helm/profiles/custom-profile.yaml
# custom-profile.yaml 편집
```

## 성능 벤치마크

### 8GB Profile
- 동시 사용자: ~50명
- Kafka 처리량: ~1000 msg/sec
- PostgreSQL TPS: ~500-1000

### 16GB Profile (Default)
- 동시 사용자: ~100-200명
- Kafka 처리량: ~2500 msg/sec
- PostgreSQL TPS: ~1000-2000

### 32GB Profile
- 동시 사용자: ~500명
- Kafka 처리량: ~5000 msg/sec
- PostgreSQL TPS: ~2000-5000

## 모니터링

프로파일 적용 후 리소스 사용량 확인:

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods --all-namespaces

# 특정 namespace
kubectl top pods -n infra
kubectl top pods -n backend
kubectl top pods -n frontend
```

## 프로파일 전환

이미 배포된 시스템의 프로파일 변경:

```bash
# 1. 현재 사용 중인 프로파일 확인
kubectl get deployment -n backend backend-service -o yaml | grep -A 5 resources

# 2. 새 프로파일로 업그레이드
helm upgrade kafka bitnami/kafka \
  --namespace infra \
  --values helm/kafka-values.yaml \
  --values helm/profiles/32gb-profile.yaml \
  --reuse-values

# 3. 롤아웃 확인
kubectl rollout status statefulset/kafka -n infra
```

## 주의사항

1. **메모리 오버커밋 방지**: 총 request 메모리가 물리 RAM의 80%를 넘지 않도록 주의
2. **CPU 제한**: 멀티코어 환경에서도 단일 Pod가 모든 CPU를 독점하지 않도록 제한
3. **점진적 확장**: 리소스를 점진적으로 증가시키며 성능 모니터링
4. **스왑 비활성화**: macOS 스왑이 과도하게 사용되면 성능 저하 가능
