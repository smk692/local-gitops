-- 계정 관리 시스템 스키마
-- Google OAuth2 + 화이트리스트 기반 인증

-- 1. 화이트리스트 테이블
CREATE TABLE IF NOT EXISTS allowed_emails (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    added_by VARCHAR(255),
    notes TEXT
);

-- 2. 사용자 테이블
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255),
    picture_url TEXT,
    first_login TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    login_count INT DEFAULT 1
);

-- 3. 로그인 이력 테이블
CREATE TABLE IF NOT EXISTS login_history (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL,
    login_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address VARCHAR(50),
    user_agent TEXT
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_login_history_email ON login_history(user_email);
CREATE INDEX IF NOT EXISTS idx_login_history_date ON login_history(login_at DESC);

-- 초기 데이터: 관리자 이메일 추가 (여기에 본인 Gmail 주소 입력)
INSERT INTO allowed_emails (email, added_by, notes)
VALUES
    ('admin@gmail.com', 'system', '초기 관리자 계정 - 본인 이메일로 변경하세요')
ON CONFLICT (email) DO NOTHING;

-- 테이블 생성 확인
SELECT
    'allowed_emails' as table_name,
    COUNT(*) as row_count
FROM allowed_emails
UNION ALL
SELECT
    'users' as table_name,
    COUNT(*) as row_count
FROM users
UNION ALL
SELECT
    'login_history' as table_name,
    COUNT(*) as row_count
FROM login_history;
