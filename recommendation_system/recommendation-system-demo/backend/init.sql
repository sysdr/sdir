CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    description TEXT,
    features JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS interactions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    item_id INTEGER REFERENCES items(id),
    interaction_type VARCHAR(50) NOT NULL,
    rating FLOAT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS recommendations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    item_id INTEGER REFERENCES items(id),
    algorithm VARCHAR(100),
    score FLOAT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email) VALUES 
    ('alice', 'alice@example.com'),
    ('bob', 'bob@example.com'),
    ('charlie', 'charlie@example.com'),
    ('diana', 'diana@example.com');

INSERT INTO items (title, category, description, features) VALUES 
    ('The Matrix', 'Sci-Fi', 'A computer hacker discovers reality is a simulation', '{"genre": "sci-fi", "year": 1999, "director": "Wachowski"}'),
    ('Inception', 'Sci-Fi', 'A thief enters dreams to plant ideas', '{"genre": "sci-fi", "year": 2010, "director": "Nolan"}'),
    ('Pulp Fiction', 'Crime', 'Interconnected criminal stories', '{"genre": "crime", "year": 1994, "director": "Tarantino"}'),
    ('The Godfather', 'Crime', 'The story of a mafia family', '{"genre": "crime", "year": 1972, "director": "Coppola"}'),
    ('Forrest Gump', 'Drama', 'Life story of an extraordinary man', '{"genre": "drama", "year": 1994, "director": "Zemeckis"}'),
    ('Titanic', 'Romance', 'Love story on the doomed ship', '{"genre": "romance", "year": 1997, "director": "Cameron"}');

-- Insert sample interactions
INSERT INTO interactions (user_id, item_id, interaction_type, rating) VALUES 
    (1, 1, 'view', 5.0),
    (1, 2, 'view', 4.5),
    (1, 3, 'view', 3.0),
    (2, 3, 'view', 5.0),
    (2, 4, 'view', 4.0),
    (2, 1, 'view', 3.5),
    (3, 5, 'view', 5.0),
    (3, 6, 'view', 4.5),
    (4, 2, 'view', 5.0),
    (4, 1, 'view', 4.0);
