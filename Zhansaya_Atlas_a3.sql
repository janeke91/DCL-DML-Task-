SET search_path TO library_physical_db;


-- cleanup: drop users and roles before recreating (makes script re-runnable)

REVOKE ALL ON ALL TABLES IN SCHEMA library_physical_db FROM dvdrental_readonly;
REVOKE ALL ON ALL TABLES IN SCHEMA library_physical_db FROM dvdrental_admin;
REVOKE ALL ON SCHEMA library_physical_db FROM dvdrental_readonly;
REVOKE ALL ON SCHEMA library_physical_db FROM dvdrental_admin;

DROP USER IF EXISTS db_admin_user;
DROP USER IF EXISTS db_reader_user;
DROP ROLE IF EXISTS dvdrental_admin;
DROP ROLE IF EXISTS dvdrental_readonly;


-- part a: dcl — roles and permissions

-- a1: create roles
CREATE ROLE dvdrental_admin;
CREATE ROLE dvdrental_readonly;

-- grant schema access to both roles
GRANT USAGE ON SCHEMA library_physical_db TO dvdrental_admin;
GRANT USAGE ON SCHEMA library_physical_db TO dvdrental_readonly;

-- admin gets full access
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA library_physical_db TO dvdrental_admin;

-- readonly gets select only
GRANT SELECT ON ALL TABLES IN SCHEMA library_physical_db TO dvdrental_readonly;

-- a2: create users and assign roles
CREATE USER db_admin_user WITH PASSWORD 'admin123';
CREATE USER db_reader_user WITH PASSWORD 'reader123';

GRANT dvdrental_admin TO db_admin_user;
GRANT dvdrental_readonly TO db_reader_user;

-- a3: revoke update and delete from readonly as a safety measure
REVOKE UPDATE, DELETE ON ALL TABLES IN SCHEMA library_physical_db FROM dvdrental_readonly;

-- \dp borrowers output:
-- library_physical_db | borrowers | table | postgres=arwdDxt/postgres          +|
--                     |           |       | dvdrental_admin=arwdDxt/postgres   +|
--                     |           |       | dvdrental_readonly=r/postgres        |
-- dvdrental_readonly has only r (select) — correct

-- a3a: verify db_admin_user — all operations should succeed
SET ROLE db_admin_user;
SELECT current_user;
SELECT COUNT(*) FROM borrowers;
INSERT INTO borrowers (first_name, last_name, email, phone, address, registration_date)
VALUES ('Test', 'Admin', 'test.admin@mail.kz', '+77099999999', 'Almaty', '2026-05-01')
RETURNING *;
UPDATE borrowers SET phone = '+77099999900' WHERE email = 'test.admin@mail.kz';
DELETE FROM borrowers WHERE borrower_id = (SELECT MAX(borrower_id) FROM borrowers);
RESET ROLE;

-- a3a: verify db_reader_user — insert, update, delete should fail
SET ROLE db_reader_user;
SELECT current_user;
SELECT COUNT(*) FROM borrowers;

BEGIN;
INSERT INTO borrowers (first_name, last_name, email, phone, address, registration_date)
VALUES ('Test', 'Reader', 'test.reader@mail.kz', '+77088888888', 'Astana', '2026-05-01')
RETURNING *;
-- ERROR:  permission denied for table borrowers
ROLLBACK;

BEGIN;
UPDATE borrowers SET phone = '+77088888800' WHERE email = 'arman.s@mail.kz';
-- ERROR:  permission denied for table borrowers
ROLLBACK;

BEGIN;
DELETE FROM borrowers WHERE borrower_id = 1;
-- ERROR:  permission denied for table borrowers
ROLLBACK;

RESET ROLE;

-- a4: drop reader user and readonly role
DROP USER IF EXISTS db_reader_user;
DROP ROLE IF EXISTS dvdrental_readonly;


-- part b: dml — insert

-- b5: truncate in correct fk order (children before parents)
TRUNCATE TABLE reservations, fines, loans, library_staff, borrowers,
               catalog, book_authors, books, authors, genres
RESTART IDENTITY CASCADE;

-- b6: insert 5+ rows per table with realistic data

INSERT INTO genres (genre_name) VALUES
    ('Classic'),
    ('Fantasy'),
    ('Science Fiction'),
    ('Detective'),
    ('Biography');

INSERT INTO authors (first_name, last_name, birth_date, nationality) VALUES
    ('Abai',    'Kunanbayuly', '1845-08-10', 'Kazakh'),
    ('J.K.',    'Rowling',     '1965-07-31', 'British'),
    ('Agatha',  'Christie',    '1890-09-15', 'British'),
    ('Mukhtar', 'Auezov',      '1897-09-28', 'Kazakh'),
    ('George',  'Orwell',      '1903-06-25', 'British');

INSERT INTO books (title, isbn, year_published, genre_id) VALUES
    ('The Book of Words',            '978-0001', 1890,
        (SELECT genre_id FROM genres WHERE genre_name = 'Classic')),
    ('Harry Potter',                 '978-0002', 1997,
        (SELECT genre_id FROM genres WHERE genre_name = 'Fantasy')),
    ('Murder on the Orient Express', '978-0003', 1934,
        (SELECT genre_id FROM genres WHERE genre_name = 'Detective')),
    ('Path of Abai',                 '978-0004', 1942,
        (SELECT genre_id FROM genres WHERE genre_name = 'Classic')),
    ('1984',                         '978-0005', 1949,
        (SELECT genre_id FROM genres WHERE genre_name = 'Science Fiction'));

INSERT INTO book_authors (book_id, author_id) VALUES
    ((SELECT book_id FROM books WHERE isbn = '978-0001'),
     (SELECT author_id FROM authors WHERE last_name = 'Kunanbayuly')),
    ((SELECT book_id FROM books WHERE isbn = '978-0002'),
     (SELECT author_id FROM authors WHERE last_name = 'Rowling')),
    ((SELECT book_id FROM books WHERE isbn = '978-0003'),
     (SELECT author_id FROM authors WHERE last_name = 'Christie')),
    ((SELECT book_id FROM books WHERE isbn = '978-0004'),
     (SELECT author_id FROM authors WHERE last_name = 'Auezov')),
    ((SELECT book_id FROM books WHERE isbn = '978-0005'),
     (SELECT author_id FROM authors WHERE last_name = 'Orwell'));

INSERT INTO catalog (book_id, shelf_location, section, status) VALUES
    ((SELECT book_id FROM books WHERE isbn = '978-0001'), 'A-10', 'Kazakh Literature', 'Available'),
    ((SELECT book_id FROM books WHERE isbn = '978-0002'), 'B-01', 'Foreign Fiction',   'Available'),
    ((SELECT book_id FROM books WHERE isbn = '978-0003'), 'C-05', 'Detective',         'Available'),
    ((SELECT book_id FROM books WHERE isbn = '978-0004'), 'A-11', 'Kazakh Literature', 'Loaned'),
    ((SELECT book_id FROM books WHERE isbn = '978-0005'), 'C-08', 'Foreign Fiction',   'Available');

INSERT INTO borrowers (first_name, last_name, email, phone, address, registration_date) VALUES
    ('Arman',   'Sabit',    'arman.s@mail.kz',   '+77011112233', 'Atyrau',   '2026-02-10'),
    ('Aizat',   'Bekova',   'aizat.b@mail.kz',   '+77022223344', 'Almaty',   '2026-02-15'),
    ('Daniyar', 'Akhmet',   'daniyar.a@mail.kz', '+77033334455', 'Astana',   '2026-03-01'),
    ('Madina',  'Nurova',   'madina.n@mail.kz',  '+77044445566', 'Shymkent', '2026-03-10'),
    ('Yerlan',  'Seitkali', 'yerlan.s@mail.kz',  '+77055556677', 'Kostanay', '2026-04-01');

INSERT INTO library_staff (first_name, last_name, email, phone, iin, role, hire_date) VALUES
    ('Ivan',  'Ivanov',    'ivan.i@lib.kz',  '+77001234567', '123456789012', 'Manager',   '2026-01-10'),
    ('Assel', 'Nurlan',    'assel.n@lib.kz', '+77002345678', '234567890123', 'Librarian', '2026-01-15'),
    ('Bakyt', 'Dzhakov',   'bakyt.d@lib.kz', '+77003456789', '345678901234', 'Librarian', '2026-02-01'),
    ('Saule', 'Akhmetova', 'saule.a@lib.kz', '+77004567890', '456789012345', 'Librarian', '2026-02-10'),
    ('Timur', 'Bekov',     'timur.b@lib.kz', '+77005678901', '567890123456', 'Assistant', '2026-03-01');

INSERT INTO loans (catalog_id, borrower_id, staff_id, loan_date) VALUES
    ((SELECT catalog_id FROM catalog WHERE shelf_location = 'A-10'),
     (SELECT borrower_id FROM borrowers WHERE email = 'arman.s@mail.kz'),
     (SELECT staff_id FROM library_staff WHERE iin = '123456789012'), '2026-04-01'),
    ((SELECT catalog_id FROM catalog WHERE shelf_location = 'B-01'),
     (SELECT borrower_id FROM borrowers WHERE email = 'aizat.b@mail.kz'),
     (SELECT staff_id FROM library_staff WHERE iin = '234567890123'), '2026-04-05'),
    ((SELECT catalog_id FROM catalog WHERE shelf_location = 'C-05'),
     (SELECT borrower_id FROM borrowers WHERE email = 'daniyar.a@mail.kz'),
     (SELECT staff_id FROM library_staff WHERE iin = '345678901234'), '2026-04-10'),
    ((SELECT catalog_id FROM catalog WHERE shelf_location = 'A-11'),
     (SELECT borrower_id FROM borrowers WHERE email = 'madina.n@mail.kz'),
     (SELECT staff_id FROM library_staff WHERE iin = '456789012345'), '2026-04-15'),
    ((SELECT catalog_id FROM catalog WHERE shelf_location = 'C-08'),
     (SELECT borrower_id FROM borrowers WHERE email = 'yerlan.s@mail.kz'),
     (SELECT staff_id FROM library_staff WHERE iin = '567890123456'), '2026-04-20');

INSERT INTO fines (loan_id, amount, status) VALUES
    ((SELECT loan_id FROM loans WHERE loan_date = '2026-04-01'), 500.00, 'Unpaid'),
    ((SELECT loan_id FROM loans WHERE loan_date = '2026-04-05'), 200.00, 'Paid'),
    ((SELECT loan_id FROM loans WHERE loan_date = '2026-04-10'),   0.00, 'None'),
    ((SELECT loan_id FROM loans WHERE loan_date = '2026-04-15'), 300.00, 'Unpaid'),
    ((SELECT loan_id FROM loans WHERE loan_date = '2026-04-20'), 100.00, 'Paid');

INSERT INTO reservations (book_id, borrower_id, reservation_date, status, res_type) VALUES
    ((SELECT book_id FROM books WHERE isbn = '978-0001'),
     (SELECT borrower_id FROM borrowers WHERE email = 'arman.s@mail.kz'),   '2026-04-01', 'Active',    'Online'),
    ((SELECT book_id FROM books WHERE isbn = '978-0002'),
     (SELECT borrower_id FROM borrowers WHERE email = 'aizat.b@mail.kz'),   '2026-04-05', 'Completed', 'Physical'),
    ((SELECT book_id FROM books WHERE isbn = '978-0003'),
     (SELECT borrower_id FROM borrowers WHERE email = 'daniyar.a@mail.kz'), '2026-04-10', 'Cancelled', 'Online'),
    ((SELECT book_id FROM books WHERE isbn = '978-0004'),
     (SELECT borrower_id FROM borrowers WHERE email = 'madina.n@mail.kz'),  '2026-04-15', 'Active',    'Physical'),
    ((SELECT book_id FROM books WHERE isbn = '978-0005'),
     (SELECT borrower_id FROM borrowers WHERE email = 'yerlan.s@mail.kz'),  '2026-04-20', 'Active',    'Online');


-- part c: dml — update

-- c7: borrower updated their phone number
SELECT borrower_id, first_name, last_name, phone
FROM borrowers
WHERE email = 'arman.s@mail.kz';
-- 1 row

UPDATE borrowers
SET phone = '+77019998877'
WHERE email = 'arman.s@mail.kz';

-- c7: book was returned, catalog status updated to available
SELECT catalog_id, shelf_location, status
FROM catalog
WHERE shelf_location = 'A-11';
-- 1 row

UPDATE catalog
SET status = 'Available'
WHERE shelf_location = 'A-11';

-- c8: mark fine as paid for loans that have a return date
UPDATE loans
SET return_date = '2026-04-20'
WHERE loan_date = '2026-04-05';

SELECT f.fine_id, f.status, l.return_date
FROM fines f
JOIN loans l ON f.loan_id = l.loan_id
WHERE l.return_date IS NOT NULL;
-- 1 row

UPDATE fines f
SET status = 'Paid'
FROM loans l
WHERE f.loan_id = l.loan_id
  AND l.return_date IS NOT NULL;


-- part d: dml — delete

-- d10: cancelled reservations are removed because they are logically obsolete.
-- borrowers who cancelled did not follow through, and keeping these records
-- pollutes active reservation reports and confuses library staff.

BEGIN;

DELETE FROM reservations
WHERE status = 'Cancelled';

SELECT COUNT(*) FROM reservations;
-- 4 rows (was 5, deleted 1 cancelled reservation)

ROLLBACK;
