-- Инициализация базы данных SaaS-платформы
-- PostgreSQL version 12+

-- Создание расширений
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

------------------------------------------------------------------------------
-- 1. ЯДРО ПЛАТФОРМЫ
------------------------------------------------------------------------------

-- Клиенты (компании)
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255) NOT NULL,
    tax_id VARCHAR(50),
    address TEXT,
    contact_person VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
COMMENT ON TABLE clients IS 'Клиенты (компании), использующие платформу';

-- Порталы (изолированные среды)
CREATE TABLE portals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    logo_url VARCHAR(255),
    primary_color VARCHAR(20),
    currency_code CHAR(3) DEFAULT 'USD',
    timezone VARCHAR(50) DEFAULT 'UTC',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE UNIQUE INDEX idx_portal_subdomain ON portals(subdomain);
COMMENT ON TABLE portals IS 'Изолированные среды (порталы) для каждого клиента';

-- Валюты
CREATE TABLE currencies (
    code CHAR(3) PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    decimal_places SMALLINT DEFAULT 2,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE currencies IS 'Справочник валют для мультивалютности';

-- Пользователи (глобальные)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(50),
    avatar_url VARCHAR(255),
    locale VARCHAR(10) DEFAULT 'en',
    is_superadmin BOOLEAN DEFAULT FALSE,
    is_platform_admin BOOLEAN DEFAULT FALSE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE UNIQUE INDEX idx_user_email ON users(email);
COMMENT ON TABLE users IS 'Глобальные пользователи платформы (один email может быть в нескольких порталах)';

-- Связь пользователей с порталами
CREATE TABLE portal_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'user',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB,
    UNIQUE (portal_id, user_id)
);
CREATE INDEX idx_portal_users_portal_id ON portal_users(portal_id);
CREATE INDEX idx_portal_users_user_id ON portal_users(user_id);
COMMENT ON TABLE portal_users IS 'Связь между пользователями и порталами (роль, доступ)';

-- Модули системы
CREATE TABLE modules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    version VARCHAR(20),
    is_core BOOLEAN DEFAULT FALSE,
    dependencies JSONB, -- Зависимости от других модулей
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE modules IS 'Доступные модули системы';

-- Тарифные планы
CREATE TABLE plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    max_users INT,
    max_storage_gb INT,
    price_monthly DECIMAL(12, 2),
    price_yearly DECIMAL(12, 2),
    features JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE plans IS 'Тарифные планы для клиентов';

-- Цены модулей в разных валютах
CREATE TABLE module_prices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    module_id UUID NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    currency_code CHAR(3) NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
    price_monthly DECIMAL(12, 2) NOT NULL,
    price_yearly DECIMAL(12, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (module_id, currency_code)
);
COMMENT ON TABLE module_prices IS 'Цены модулей в разных валютах';

-- Подключенные модули портала
CREATE TABLE portal_modules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    module_id UUID NOT NULL REFERENCES modules(id) ON DELETE RESTRICT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    activated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    settings JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (portal_id, module_id)
);
CREATE INDEX idx_portal_modules_portal_id ON portal_modules(portal_id);
COMMENT ON TABLE portal_modules IS 'Модули, подключенные к конкретному порталу';

-- Подписки клиентов
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending', 'cancelled')),
    start_date DATE NOT NULL,
    end_date DATE,
    billing_cycle VARCHAR(20) DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly', 'yearly')),
    price DECIMAL(12, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
    auto_renew BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_subscriptions_portal_id ON subscriptions(portal_id);
COMMENT ON TABLE subscriptions IS 'Подписки клиентов на платформу';

-- Платежи
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    amount DECIMAL(12, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
    payment_method VARCHAR(50),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    transaction_id VARCHAR(255),
    payment_date TIMESTAMP WITH TIME ZONE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_payments_portal_id ON payments(portal_id);
COMMENT ON TABLE payments IS 'История платежей клиентов';

-- Счета
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    invoice_number VARCHAR(50) NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    currency_code CHAR(3) NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled', 'overdue')),
    issue_date DATE NOT NULL,
    due_date DATE NOT NULL,
    paid_date DATE,
    pdf_url VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_invoices_portal_id ON invoices(portal_id);
COMMENT ON TABLE invoices IS 'Счета, выставленные клиентам';

-- API ключи
CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    api_key VARCHAR(255) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    permissions JSONB,
    expires_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_api_keys_portal_id ON api_keys(portal_id);
COMMENT ON TABLE api_keys IS 'API ключи для интеграций';

-- Резервные копии
CREATE TABLE backups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    size_bytes BIGINT,
    backup_type VARCHAR(50) DEFAULT 'full' CHECK (backup_type IN ('full', 'structure', 'data')),
    status VARCHAR(20) DEFAULT 'completed' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
    storage_path VARCHAR(255),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_backups_portal_id ON backups(portal_id);
COMMENT ON TABLE backups IS 'Резервные копии данных портала';

-- Журнал действий
CREATE TABLE log_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID REFERENCES portals(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action_type VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_log_actions_portal_id ON log_actions(portal_id);
CREATE INDEX idx_log_actions_created_at ON log_actions(created_at);
COMMENT ON TABLE log_actions IS 'Журнал действий пользователей и системы';

------------------------------------------------------------------------------
-- 2. МОДУЛЬ СТРУКТУРЫ КОМПАНИИ
------------------------------------------------------------------------------

-- Отделы
CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES departments(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50),
    description TEXT,
    head_position_id UUID, -- Внешний ключ будет установлен позже
    is_active BOOLEAN DEFAULT TRUE,
    order_index INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_departments_portal_id ON departments(portal_id);
CREATE INDEX idx_departments_parent_id ON departments(parent_id);
COMMENT ON TABLE departments IS 'Отделы компании с иерархической структурой';

-- Должности (позиции)
CREATE TABLE positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50),
    description TEXT,
    is_manager BOOLEAN DEFAULT FALSE,
    grade VARCHAR(50),
    number_of_vacancies INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    order_index INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_positions_portal_id ON positions(portal_id);
CREATE INDEX idx_positions_department_id ON positions(department_id);
COMMENT ON TABLE positions IS 'Должности (позиции) в отделах';

-- Добавляем внешний ключ head_position_id в departments
ALTER TABLE departments
ADD CONSTRAINT fk_departments_head_position
FOREIGN KEY (head_position_id) REFERENCES positions(id)
ON DELETE SET NULL;

-- Сотрудники
CREATE TABLE employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(50),
    hire_date DATE,
    termination_date DATE,
    employee_number VARCHAR(50),
    birth_date DATE,
    gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other')),
    photo_url VARCHAR(255),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'on_leave')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_employees_portal_id ON employees(portal_id);
CREATE INDEX idx_employees_user_id ON employees(user_id);
COMMENT ON TABLE employees IS 'Сотрудники компании';

-- Назначения сотрудников на должности (многие ко многим)
CREATE TABLE employee_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    position_id UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
    is_primary BOOLEAN DEFAULT TRUE,
    start_date DATE NOT NULL,
    end_date DATE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (employee_id, position_id, start_date)
);
CREATE INDEX idx_employee_positions_portal_id ON employee_positions(portal_id);
CREATE INDEX idx_employee_positions_employee_id ON employee_positions(employee_id);
CREATE INDEX idx_employee_positions_position_id ON employee_positions(position_id);
COMMENT ON TABLE employee_positions IS 'Связь между сотрудниками и должностями (назначения)';

-- Функциональные обязанности
CREATE TABLE functions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    position_id UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_required BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_functions_portal_id ON functions(portal_id);
CREATE INDEX idx_functions_position_id ON functions(position_id);
COMMENT ON TABLE functions IS 'Функциональные обязанности должностей';

-- Вакансии
CREATE TABLE vacancies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    position_id UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    requirements TEXT,
    is_published BOOLEAN DEFAULT FALSE,
    published_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'closed', 'draft')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_vacancies_portal_id ON vacancies(portal_id);
CREATE INDEX idx_vacancies_position_id ON vacancies(position_id);
COMMENT ON TABLE vacancies IS 'Вакансии компании';

-- Стажеры
CREATE TABLE interns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    position_id UUID REFERENCES positions(id) ON DELETE SET NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    start_date DATE NOT NULL,
    end_date DATE,
    mentor_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'terminated')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_interns_portal_id ON interns(portal_id);
CREATE INDEX idx_interns_department_id ON interns(department_id);
COMMENT ON TABLE interns IS 'Стажеры компании';

-- Кадровый резерв
CREATE TABLE reserves (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    target_position_id UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
    readiness_level VARCHAR(20) CHECK (readiness_level IN ('ready', 'in_6_months', 'in_1_year', 'in_progress')),
    development_plan TEXT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    extra_data JSONB
);
CREATE INDEX idx_reserves_portal_id ON reserves(portal_id);
CREATE INDEX idx_reserves_employee_id ON reserves(employee_id);
COMMENT ON TABLE reserves IS 'Кадровый резерв компании';

-- Роли в отделах
CREATE TABLE department_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) NOT NULL,
    description TEXT,
    permissions JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_department_roles_portal_id ON department_roles(portal_id);
COMMENT ON TABLE department_roles IS 'Роли в отделах компании';

-- Назначение ролей в отделах сотрудникам
CREATE TABLE employee_department_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    department_role_id UUID NOT NULL REFERENCES department_roles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (employee_id, department_id, department_role_id)
);
CREATE INDEX idx_employee_department_roles_portal_id ON employee_department_roles(portal_id);
COMMENT ON TABLE employee_department_roles IS 'Назначение ролей сотрудникам в отделах';

-- Настройки структуры
CREATE TABLE structure_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    setting_key VARCHAR(100) NOT NULL,
    setting_value JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (portal_id, setting_key)
);
CREATE INDEX idx_structure_settings_portal_id ON structure_settings(portal_id);
COMMENT ON TABLE structure_settings IS 'Настройки структуры компании';

-- Видимость элементов структуры
CREATE TABLE visibility_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    entity_type VARCHAR(50) NOT NULL CHECK (entity_type IN ('department', 'position', 'employee', 'function')),
    entity_id UUID NOT NULL,
    is_visible BOOLEAN DEFAULT TRUE,
    visible_for JSONB, -- Кому видно (роли/группы)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (portal_id, entity_type, entity_id)
);
CREATE INDEX idx_visibility_settings_portal_id ON visibility_settings(portal_id);
COMMENT ON TABLE visibility_settings IS 'Настройки видимости элементов структуры';

-- Права доступа
CREATE TABLE access_rights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    role_id UUID NOT NULL, -- Может ссылаться на department_roles или portal_users.role
    entity_type VARCHAR(50) NOT NULL,
    permission VARCHAR(50) NOT NULL,
    is_allowed BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (portal_id, role_id, entity_type, permission)
);
CREATE INDEX idx_access_rights_portal_id ON access_rights(portal_id);
COMMENT ON TABLE access_rights IS 'Права доступа к элементам системы';

-- Версии структуры
CREATE TABLE structure_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portal_id UUID NOT NULL REFERENCES portals(id) ON DELETE CASCADE,
    version_number INT NOT NULL,
    description TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    structure_data JSONB NOT NULL, -- Полная структура на момент создания версии
    is_current BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_structure_versions_portal_id ON structure_versions(portal_id);
CREATE UNIQUE INDEX idx_structure_versions_current ON structure_versions(portal_id) WHERE is_current = TRUE;
COMMENT ON TABLE structure_versions IS 'Версии структуры компании (хранение 5 последних)';

-- Триггерная функция для ограничения количества версий
CREATE OR REPLACE FUNCTION limit_structure_versions() 
RETURNS TRIGGER AS $$
BEGIN
    -- Удаляем старые версии, оставляя только 5 последних для каждого портала
    DELETE FROM structure_versions
    WHERE id IN (
        SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY portal_id ORDER BY version_number DESC) as row_num
            FROM structure_versions
            WHERE portal_id = NEW.portal_id
        ) ranked
        WHERE row_num > 5
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для ограничения количества версий
CREATE TRIGGER trg_limit_structure_versions
AFTER INSERT ON structure_versions
FOR EACH ROW
EXECUTE FUNCTION limit_structure_versions();

------------------------------------------------------------------------------
-- 3. ПРЕДСТАВЛЕНИЯ
------------------------------------------------------------------------------

-- Представление для текущей структуры компании
CREATE VIEW current_company_structure AS
SELECT 
    d.id AS department_id,
    d.portal_id,
    d.name AS department_name,
    d.parent_id AS parent_department_id,
    p.id AS position_id,
    p.name AS position_name,
    p.is_manager,
    e.id AS employee_id,
    e.first_name || ' ' || e.last_name AS employee_name
FROM 
    departments d
LEFT JOIN positions p ON p.department_id = d.id
LEFT JOIN employee_positions ep ON ep.position_id = p.id AND ep.is_primary = TRUE AND ep.status = 'active'
LEFT JOIN employees e ON e.id = ep.employee_id AND e.status = 'active'
WHERE 
    d.is_active = TRUE
    AND (p.id IS NULL OR p.is_active = TRUE);

-- Представление активных модулей портала
CREATE VIEW active_portal_modules AS
SELECT 
    pm.portal_id,
    p.name AS portal_name,
    m.id AS module_id,
    m.name AS module_name,
    m.code AS module_code,
    pm.activated_at,
    pm.expires_at
FROM 
    portal_modules pm
JOIN portals p ON p.id = pm.portal_id
JOIN modules m ON m.id = pm.module_id
WHERE 
    pm.status = 'active'
    AND (pm.expires_at IS NULL OR pm.expires_at > NOW());

------------------------------------------------------------------------------
-- 4. ИНДЕКСЫ
------------------------------------------------------------------------------

-- Поиск по подстроке имени/названия для всех основных таблиц
CREATE INDEX idx_clients_name_trgm ON clients USING gin (name gin_trgm_ops);
CREATE INDEX idx_portals_name_trgm ON portals USING gin (name gin_trgm_ops);
CREATE INDEX idx_departments_name_trgm ON departments USING gin (name gin_trgm_ops);
CREATE INDEX idx_positions_name_trgm ON positions USING gin (name gin_trgm_ops);
CREATE INDEX idx_employees_name_trgm ON employees USING gin (
    (first_name || ' ' || last_name) gin_trgm_ops
);

-- Индексы для фильтрации по статусу
CREATE INDEX idx_portals_status ON portals(status);
CREATE INDEX idx_employees_status ON employees(status);
CREATE INDEX idx_positions_is_active ON positions(is_active);
CREATE INDEX idx_departments_is_active ON departments(is_active);

-- Индексы по дате создания для часто используемых таблиц
CREATE INDEX idx_employees_created_at ON employees(created_at);
CREATE INDEX idx_departments_created_at ON departments(created_at);
CREATE INDEX idx_positions_created_at ON positions(created_at);
CREATE INDEX idx_portal_users_created_at ON portal_users(created_at);

------------------------------------------------------------------------------
-- 5. НАЧАЛЬНЫЕ ДАННЫЕ
------------------------------------------------------------------------------

-- Валюты
INSERT INTO currencies (code, name, symbol, decimal_places, is_active) VALUES
('USD', 'US Dollar', '$', 2, TRUE),
('EUR', 'Euro', '€', 2, TRUE),
('GBP', 'British Pound', '£', 2, TRUE),
('RUB', 'Russian Ruble', '₽', 2, TRUE);

-- Базовые модули
INSERT INTO modules (name, code, description, is_core, version) VALUES
('Центральная админка', 'core', 'Ядро платформы для управления клиентами и порталами', TRUE, '1.0.0'),
('Структура компании', 'structure', 'Модуль для управления организационной структурой', TRUE, '1.0.0'),
('Документы', 'documents', 'Модуль для работы с документами и файлами', FALSE, '1.0.0'),
('Задачи', 'tasks', 'Модуль для управления задачами и проектами', FALSE, '1.0.0'),
('Календарь', 'calendar', 'Модуль календаря и планирования', FALSE, '1.0.0'),
('Обучение', 'learning', 'Модуль для создания и управления обучающими материалами', FALSE, '1.0.0');

-- Базовые роли для отделов
INSERT INTO department_roles (id, portal_id, name, code, description, permissions) VALUES
('00000000-0000-0000-0000-000000000001', NULL, 'Руководитель', 'head', 'Руководитель отдела', '{"manage_structure": true, "manage_employees": true, "view_all": true}'),
('00000000-0000-0000-0000-000000000002', NULL, 'Заместитель', 'deputy', 'Заместитель руководителя', '{"manage_employees": true, "view_all": true}'),
('00000000-0000-0000-0000-000000000003', NULL, 'HR-специалист', 'hr', 'Специалист по персоналу', '{"manage_employees": true, "view_all": true}'),
('00000000-0000-0000-0000-000000000004', NULL, 'Сотрудник', 'employee', 'Обычный сотрудник', '{"view_own_department": true}');