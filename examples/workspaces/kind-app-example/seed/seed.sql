-- TODO App Seed Data
-- This file can be used to seed the database with initial data

CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO tasks (title, description, completed) VALUES
('Buy groceries', 'Milk, eggs, bread, and cheese', false),
('Review pull request', 'Check the new feature branch for issues', false),
('Schedule dentist appointment', 'Call Dr. Smith office', false),
('Finish reading book', 'Complete chapters 10-12 of Clean Code', true),
('Update resume', 'Add recent project experience', false)
ON CONFLICT DO NOTHING;
