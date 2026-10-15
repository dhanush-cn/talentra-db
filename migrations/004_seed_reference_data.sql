-- 004_seed_reference_data.sql
-- Purpose : reference rows every environment needs (not the bulk synthetic data,
--           which the generator produces).
-- Owner   : Master data (whole team, Phase 1)
-- Sources : ISO 639, ISO 4217, ISO 3166-1/-2 (codes as of the 2023 ISO 3166-2:IN update);
--           city coordinates entered manually (approximate city centres), source = MANUAL.
-- Hindi and Kannada display names are drafts and need a native-speaker review before submission.

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';   -- system account

-- ---------------------------------------------------------------------------
-- Languages (English is the default and fallback)
-- ---------------------------------------------------------------------------
INSERT INTO mst.language (iso_code, english_name, native_name, is_default, is_ui_supported, sort_order) VALUES
    ('en', 'English',   'English',   true,  true,  1),
    ('hi', 'Hindi',     'हिन्दी',      false, true,  2),
    ('kn', 'Kannada',   'ಕನ್ನಡ',      false, true,  3),
    ('ta', 'Tamil',     'தமிழ்',      false, false, 4),
    ('te', 'Telugu',    'తెలుగు',     false, false, 5),
    ('ml', 'Malayalam', 'മലയാളം',    false, false, 6),
    ('mr', 'Marathi',   'मराठी',      false, false, 7),
    ('bn', 'Bengali',   'বাংলা',      false, false, 8),
    ('gu', 'Gujarati',  'ગુજરાતી',    false, false, 9);

-- ---------------------------------------------------------------------------
-- Enumerations shared across modules.
-- Module-specific enumerations are added by the owning module's migration.
-- ---------------------------------------------------------------------------
INSERT INTO mst.code_type (code, english_name, description, owning_module) VALUES
    ('JOB_CATEGORY',        'Job category',        'Business category of a job or gig request (Section 2).', 'JOB'),
    ('EMPLOYMENT_TYPE',     'Employment type',     'Contractual nature of the role.', 'JOB'),
    ('WORK_TYPE',           'Work type',           'Where the work is performed.', 'JOB'),
    ('APPLICATION_STATUS',  'Application status',  'Pipeline stage of an application.', 'JOB'),
    ('PROFICIENCY_LEVEL',   'Proficiency level',   'Self-assessed or assessed level for skills and languages.', 'PRF'),
    ('TAX_ID_TYPE',         'Tax or registration identifier type', 'Kind of identifier held for an organisation.', 'ORG'),
    ('DISCLOSURE_STATUS',   'Disclosure status',   'Distinguishes not disclosed, not applicable and unknown (Rule 5).', 'MST'),
    ('VERIFICATION_STATUS', 'Verification status', 'Outcome of an external verification.', 'MST');

CREATE TEMP TABLE seed_code (
    code_type  text,
    code       text,
    sort_order smallint,
    name_en    text,
    name_hi    text,
    name_kn    text
) ON COMMIT DROP;

INSERT INTO seed_code VALUES
    -- APPLICATION_STATUS (pipeline order)
    ('APPLICATION_STATUS', 'APPLIED',     10, 'Applied',     'आवेदन किया',            'ಅರ್ಜಿ ಸಲ್ಲಿಸಲಾಗಿದೆ'),
    ('APPLICATION_STATUS', 'SHORTLISTED', 20, 'Shortlisted', 'शॉर्टलिस्ट किया गया',      'ಆಯ್ಕೆ ಪಟ್ಟಿಯಲ್ಲಿದೆ'),
    ('APPLICATION_STATUS', 'INTERVIEWED', 30, 'Interviewed', 'साक्षात्कार हुआ',          'ಸಂದರ್ಶನ ನಡೆದಿದೆ'),
    ('APPLICATION_STATUS', 'OFFERED',     40, 'Offered',     'प्रस्ताव दिया गया',        'ಆಫರ್ ನೀಡಲಾಗಿದೆ'),
    ('APPLICATION_STATUS', 'JOINED',      50, 'Joined',      'शामिल हुए',              'ಸೇರಿದ್ದಾರೆ'),
    ('APPLICATION_STATUS', 'REJECTED',    60, 'Rejected',    'अस्वीकृत',               'ತಿರಸ್ಕರಿಸಲಾಗಿದೆ'),
    ('APPLICATION_STATUS', 'WITHDRAWN',   70, 'Withdrawn',   'वापस लिया गया',           'ಹಿಂಪಡೆಯಲಾಗಿದೆ'),
    -- WORK_TYPE
    ('WORK_TYPE', 'ONSITE', 10, 'On-site', 'कार्यालय से',   'ಕಚೇರಿಯಿಂದ'),
    ('WORK_TYPE', 'REMOTE', 20, 'Remote',  'घर से / रिमोट', 'ರಿಮೋಟ್'),
    ('WORK_TYPE', 'HYBRID', 30, 'Hybrid',  'हाइब्रिड',      'ಹೈಬ್ರಿಡ್'),
    -- JOB_CATEGORY (Section 2)
    ('JOB_CATEGORY', 'GIG_PROJECT',            10, 'Gig and project-based work', NULL, NULL),
    ('JOB_CATEGORY', 'GENERAL_STAFFING',       20, 'General staffing',           NULL, NULL),
    ('JOB_CATEGORY', 'PROFESSIONAL_STAFFING',  30, 'Professional staffing',      NULL, NULL),
    ('JOB_CATEGORY', 'PERMANENT',              40, 'Permanent full-time',        NULL, NULL),
    ('JOB_CATEGORY', 'APPRENTICE',             50, 'Apprentice hiring',          NULL, NULL),
    ('JOB_CATEGORY', 'CAMPUS_FRESHER',         60, 'Campus and fresher hiring',  NULL, NULL),
    ('JOB_CATEGORY', 'CONSULTANT_MARKETPLACE', 70, 'Consultant marketplace',     NULL, NULL),
    ('JOB_CATEGORY', 'MANAGED_REMOTE',         80, 'Managed remote workforce',   NULL, NULL),
    -- EMPLOYMENT_TYPE
    ('EMPLOYMENT_TYPE', 'FULL_TIME',     10, 'Full-time',     NULL, NULL),
    ('EMPLOYMENT_TYPE', 'PART_TIME',     20, 'Part-time',     NULL, NULL),
    ('EMPLOYMENT_TYPE', 'CONTRACT',      30, 'Contract',      NULL, NULL),
    ('EMPLOYMENT_TYPE', 'TEMPORARY',     40, 'Temporary',     NULL, NULL),
    ('EMPLOYMENT_TYPE', 'APPRENTICESHIP',50, 'Apprenticeship',NULL, NULL),
    ('EMPLOYMENT_TYPE', 'INTERNSHIP',    60, 'Internship',    NULL, NULL),
    ('EMPLOYMENT_TYPE', 'FREELANCE',     70, 'Freelance',     NULL, NULL),
    -- PROFICIENCY_LEVEL
    ('PROFICIENCY_LEVEL', 'BEGINNER',     10, 'Beginner',     NULL, NULL),
    ('PROFICIENCY_LEVEL', 'INTERMEDIATE', 20, 'Intermediate', NULL, NULL),
    ('PROFICIENCY_LEVEL', 'ADVANCED',     30, 'Advanced',     NULL, NULL),
    ('PROFICIENCY_LEVEL', 'EXPERT',       40, 'Expert',       NULL, NULL),
    -- TAX_ID_TYPE (India first; others added as countries are onboarded)
    ('TAX_ID_TYPE', 'IN_PAN',   10, 'PAN (India)',   NULL, NULL),
    ('TAX_ID_TYPE', 'IN_GSTIN', 20, 'GSTIN (India)', NULL, NULL),
    ('TAX_ID_TYPE', 'IN_CIN',   30, 'CIN (India)',   NULL, NULL),
    ('TAX_ID_TYPE', 'IN_TAN',   40, 'TAN (India)',   NULL, NULL),
    ('TAX_ID_TYPE', 'IN_LLPIN', 50, 'LLPIN (India)', NULL, NULL),
    ('TAX_ID_TYPE', 'IN_UDYAM', 60, 'Udyam registration (India)', NULL, NULL),
    -- DISCLOSURE_STATUS (Rule 5: unknown vs not applicable vs not disclosed)
    ('DISCLOSURE_STATUS', 'DISCLOSED',      10, 'Disclosed',      NULL, NULL),
    ('DISCLOSURE_STATUS', 'NOT_DISCLOSED',  20, 'Not disclosed',  NULL, NULL),
    ('DISCLOSURE_STATUS', 'NOT_APPLICABLE', 30, 'Not applicable', NULL, NULL),
    ('DISCLOSURE_STATUS', 'UNKNOWN',        40, 'Unknown',        NULL, NULL),
    -- VERIFICATION_STATUS
    ('VERIFICATION_STATUS', 'PENDING',  10, 'Pending',  NULL, NULL),
    ('VERIFICATION_STATUS', 'VERIFIED', 20, 'Verified', NULL, NULL),
    ('VERIFICATION_STATUS', 'REJECTED', 30, 'Rejected', NULL, NULL),
    ('VERIFICATION_STATUS', 'EXPIRED',  40, 'Expired',  NULL, NULL),
    -- COORDINATE_SOURCE
    ('COORDINATE_SOURCE', 'MANUAL',            10, 'Manual entry',      NULL, NULL),
    ('COORDINATE_SOURCE', 'GEOCODING_SERVICE', 20, 'Geocoding service', NULL, NULL),
    ('COORDINATE_SOURCE', 'DEVICE_GPS',        30, 'Device GPS',        NULL, NULL),
    -- SKILL_CATEGORY
    ('SKILL_CATEGORY', 'TECHNICAL',     10, 'Technical',     NULL, NULL),
    ('SKILL_CATEGORY', 'TOOL',          20, 'Tool or platform', NULL, NULL),
    ('SKILL_CATEGORY', 'DOMAIN',        30, 'Domain',        NULL, NULL),
    ('SKILL_CATEGORY', 'SOFT',          40, 'Soft skill',    NULL, NULL),
    ('SKILL_CATEGORY', 'TRADE',         50, 'Trade or vocational', NULL, NULL),
    -- QUALIFICATION_LEVEL
    ('QUALIFICATION_LEVEL', 'SECONDARY',        10, 'Secondary (Class 10)',        NULL, NULL),
    ('QUALIFICATION_LEVEL', 'HIGHER_SECONDARY', 20, 'Higher secondary (Class 12)', NULL, NULL),
    ('QUALIFICATION_LEVEL', 'VOCATIONAL',       30, 'Vocational (ITI)',            NULL, NULL),
    ('QUALIFICATION_LEVEL', 'DIPLOMA',          40, 'Diploma',                     NULL, NULL),
    ('QUALIFICATION_LEVEL', 'UNDERGRADUATE',    50, 'Undergraduate',               NULL, NULL),
    ('QUALIFICATION_LEVEL', 'POSTGRADUATE',     60, 'Postgraduate',                NULL, NULL),
    ('QUALIFICATION_LEVEL', 'DOCTORATE',        70, 'Doctorate',                   NULL, NULL),
    ('QUALIFICATION_LEVEL', 'CERTIFICATION',    80, 'Professional certification',  NULL, NULL);

INSERT INTO mst.ref_code (code_type_id, code, sort_order)
SELECT ct.id, s.code, s.sort_order
FROM seed_code s JOIN mst.code_type ct ON ct.code = s.code_type;

INSERT INTO mst.ref_code_translation (ref_code_id, language_id, display_name)
SELECT rc.id, l.id, v.display_name
FROM seed_code s
JOIN mst.code_type ct ON ct.code = s.code_type
JOIN mst.ref_code rc ON rc.code_type_id = ct.id AND rc.code = s.code
CROSS JOIN LATERAL (VALUES ('en', s.name_en), ('hi', s.name_hi), ('kn', s.name_kn)) AS v(iso, display_name)
JOIN mst.language l ON l.iso_code = v.iso
WHERE v.display_name IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Currencies and countries
-- ---------------------------------------------------------------------------
INSERT INTO mst.currency (iso_code, english_name, minor_unit, sort_order) VALUES
    ('INR', 'Indian Rupee', 2, 1),
    ('USD', 'US Dollar', 2, 2),
    ('EUR', 'Euro', 2, 3),
    ('GBP', 'Pound Sterling', 2, 4),
    ('AED', 'UAE Dirham', 2, 5),
    ('SGD', 'Singapore Dollar', 2, 6);

INSERT INTO mst.country (iso2_code, iso3_code, english_name, phone_calling_code, currency_id)
SELECT v.iso2, v.iso3, v.name, v.calling, c.id
FROM (VALUES
    ('IN', 'IND', 'India',                '91',  'INR'),
    ('US', 'USA', 'United States',        '1',   'USD'),
    ('GB', 'GBR', 'United Kingdom',       '44',  'GBP'),
    ('AE', 'ARE', 'United Arab Emirates', '971', 'AED'),
    ('SG', 'SGP', 'Singapore',            '65',  'SGD')
) AS v(iso2, iso3, name, calling, currency)
JOIN mst.currency c ON c.iso_code = v.currency;

-- ---------------------------------------------------------------------------
-- Indian states and union territories (ISO 3166-2:IN)
-- ---------------------------------------------------------------------------
INSERT INTO mst.state (country_id, iso_code, english_name, is_union_territory)
SELECT (SELECT id FROM mst.country WHERE iso2_code = 'IN'), v.code, v.name, v.ut
FROM (VALUES
    ('IN-AP', 'Andhra Pradesh', false), ('IN-AR', 'Arunachal Pradesh', false),
    ('IN-AS', 'Assam', false),          ('IN-BR', 'Bihar', false),
    ('IN-CG', 'Chhattisgarh', false),   ('IN-GA', 'Goa', false),
    ('IN-GJ', 'Gujarat', false),        ('IN-HR', 'Haryana', false),
    ('IN-HP', 'Himachal Pradesh', false), ('IN-JH', 'Jharkhand', false),
    ('IN-KA', 'Karnataka', false),      ('IN-KL', 'Kerala', false),
    ('IN-MP', 'Madhya Pradesh', false), ('IN-MH', 'Maharashtra', false),
    ('IN-MN', 'Manipur', false),        ('IN-ML', 'Meghalaya', false),
    ('IN-MZ', 'Mizoram', false),        ('IN-NL', 'Nagaland', false),
    ('IN-OD', 'Odisha', false),         ('IN-PB', 'Punjab', false),
    ('IN-RJ', 'Rajasthan', false),      ('IN-SK', 'Sikkim', false),
    ('IN-TN', 'Tamil Nadu', false),     ('IN-TS', 'Telangana', false),
    ('IN-TR', 'Tripura', false),        ('IN-UP', 'Uttar Pradesh', false),
    ('IN-UK', 'Uttarakhand', false),    ('IN-WB', 'West Bengal', false),
    ('IN-AN', 'Andaman and Nicobar Islands', true), ('IN-CH', 'Chandigarh', true),
    ('IN-DH', 'Dadra and Nagar Haveli and Daman and Diu', true), ('IN-DL', 'Delhi', true),
    ('IN-JK', 'Jammu and Kashmir', true), ('IN-LA', 'Ladakh', true),
    ('IN-LD', 'Lakshadweep', true),     ('IN-PY', 'Puducherry', true)
) AS v(code, name, ut);

-- ---------------------------------------------------------------------------
-- Major cities (approximate city-centre coordinates, manual source)
-- ---------------------------------------------------------------------------
INSERT INTO mst.city (state_id, english_name, latitude, longitude, coordinate_source_ref_code_id)
SELECT s.id, v.name, v.lat, v.lon,
       (SELECT rc.id FROM mst.ref_code rc JOIN mst.code_type ct ON ct.id = rc.code_type_id
        WHERE ct.code = 'COORDINATE_SOURCE' AND rc.code = 'MANUAL')
FROM (VALUES
    ('IN-KA', 'Bengaluru',          12.971599, 77.594566), ('IN-KA', 'Mysuru',        12.295810, 76.639381),
    ('IN-KA', 'Mangaluru',          12.914142, 74.855957), ('IN-KA', 'Hubballi',      15.364708, 75.123955),
    ('IN-KA', 'Belagavi',           15.849695, 74.497674),
    ('IN-TN', 'Chennai',            13.082680, 80.270718), ('IN-TN', 'Coimbatore',    11.016844, 76.955832),
    ('IN-TS', 'Hyderabad',          17.385044, 78.486671), ('IN-MH', 'Mumbai',        19.076090, 72.877426),
    ('IN-MH', 'Pune',               18.520430, 73.856743), ('IN-MH', 'Nagpur',        21.145800, 79.088155),
    ('IN-DL', 'New Delhi',          28.613939, 77.209023), ('IN-UP', 'Noida',         28.535517, 77.391029),
    ('IN-UP', 'Lucknow',            26.846694, 80.946166), ('IN-HR', 'Gurugram',      28.459497, 77.026638),
    ('IN-WB', 'Kolkata',            22.572646, 88.363895), ('IN-GJ', 'Ahmedabad',     23.022505, 72.571365),
    ('IN-RJ', 'Jaipur',             26.912434, 75.787271), ('IN-KL', 'Kochi',          9.931233, 76.267304),
    ('IN-KL', 'Thiruvananthapuram',  8.524139, 76.936638), ('IN-CH', 'Chandigarh',    30.733315, 76.779419),
    ('IN-OD', 'Bhubaneswar',        20.296059, 85.824539), ('IN-AP', 'Visakhapatnam', 17.686816, 83.218482),
    ('IN-MP', 'Indore',             22.719568, 75.857727), ('IN-BR', 'Patna',         25.594095, 85.137566),
    ('IN-AS', 'Guwahati',           26.144517, 91.736237)
) AS v(state_code, name, lat, lon)
JOIN mst.state s ON s.iso_code = v.state_code;

-- ---------------------------------------------------------------------------
-- Starter skills, qualifications, industries and job roles.
-- The generator extends these lists; these are the stable core.
-- ---------------------------------------------------------------------------
INSERT INTO mst.skill (english_name, skill_category_ref_code_id)
SELECT v.name, rc.id
FROM (VALUES
    ('Java','TECHNICAL'), ('Python','TECHNICAL'), ('JavaScript','TECHNICAL'), ('TypeScript','TECHNICAL'),
    ('Go','TECHNICAL'), ('C++','TECHNICAL'), ('SQL','TECHNICAL'), ('React','TECHNICAL'),
    ('Node.js','TECHNICAL'), ('Spring Boot','TECHNICAL'), ('Django','TECHNICAL'), ('Machine Learning','TECHNICAL'),
    ('Data Analysis','TECHNICAL'), ('System Design','TECHNICAL'), ('Android Development','TECHNICAL'), ('iOS Development','TECHNICAL'),
    ('PostgreSQL','TOOL'), ('MySQL','TOOL'), ('AWS','TOOL'), ('Docker','TOOL'),
    ('Kubernetes','TOOL'), ('Git','TOOL'), ('Excel','TOOL'), ('Tally','TOOL'),
    ('SAP','TOOL'), ('Figma','TOOL'), ('Salesforce','TOOL'),
    ('Accounting','DOMAIN'), ('Recruitment','DOMAIN'), ('Digital Marketing','DOMAIN'), ('Customer Support','DOMAIN'),
    ('Supply Chain','DOMAIN'), ('Banking Operations','DOMAIN'),
    ('Communication','SOFT'), ('Team Leadership','SOFT'), ('Problem Solving','SOFT'), ('Negotiation','SOFT'),
    ('Electrician','TRADE'), ('Plumbing','TRADE'), ('Welding','TRADE'), ('Driving (LMV)','TRADE'),
    ('Photography','TRADE'), ('Delivery Operations','TRADE')
) AS v(name, category)
JOIN mst.code_type ct ON ct.code = 'SKILL_CATEGORY'
JOIN mst.ref_code rc ON rc.code_type_id = ct.id AND rc.code = v.category;

INSERT INTO mst.qualification (english_name, short_name, qualification_level_ref_code_id)
SELECT v.name, v.short, rc.id
FROM (VALUES
    ('Secondary School Certificate', 'SSLC', 'SECONDARY'),
    ('Higher Secondary Certificate', 'PUC/HSC', 'HIGHER_SECONDARY'),
    ('Industrial Training Institute Certificate', 'ITI', 'VOCATIONAL'),
    ('Diploma in Engineering', 'Diploma', 'DIPLOMA'),
    ('Bachelor of Engineering', 'B.E.', 'UNDERGRADUATE'),
    ('Bachelor of Technology', 'B.Tech', 'UNDERGRADUATE'),
    ('Bachelor of Science', 'B.Sc', 'UNDERGRADUATE'),
    ('Bachelor of Commerce', 'B.Com', 'UNDERGRADUATE'),
    ('Bachelor of Computer Applications', 'BCA', 'UNDERGRADUATE'),
    ('Bachelor of Business Administration', 'BBA', 'UNDERGRADUATE'),
    ('Master of Technology', 'M.Tech', 'POSTGRADUATE'),
    ('Master of Computer Applications', 'MCA', 'POSTGRADUATE'),
    ('Master of Business Administration', 'MBA', 'POSTGRADUATE'),
    ('Master of Science', 'M.Sc', 'POSTGRADUATE'),
    ('Doctor of Philosophy', 'PhD', 'DOCTORATE'),
    ('Chartered Accountant', 'CA', 'CERTIFICATION')
) AS v(name, short, level)
JOIN mst.code_type ct ON ct.code = 'QUALIFICATION_LEVEL'
JOIN mst.ref_code rc ON rc.code_type_id = ct.id AND rc.code = v.level;

INSERT INTO mst.industry (english_name) VALUES
    ('Information Technology'), ('Banking and Financial Services'), ('Manufacturing'),
    ('Retail and E-commerce'), ('Healthcare'), ('Education'), ('Logistics and Transportation'),
    ('Construction and Real Estate'), ('Hospitality'), ('Media and Creative Services');

INSERT INTO mst.industry (parent_industry_id, english_name)
SELECT p.id, v.child
FROM (VALUES
    ('Information Technology', 'Software Products'),
    ('Information Technology', 'IT Services and Consulting'),
    ('Banking and Financial Services', 'Fintech'),
    ('Banking and Financial Services', 'Insurance')
) AS v(parent, child)
JOIN mst.industry p ON p.english_name = v.parent;

INSERT INTO mst.job_role (industry_id, english_name)
SELECT i.id, v.role
FROM (VALUES
    ('Software Products', 'Backend Engineer'), ('Software Products', 'Frontend Engineer'),
    ('Software Products', 'Full Stack Engineer'), ('Software Products', 'Data Scientist'),
    ('Software Products', 'Product Manager'), ('IT Services and Consulting', 'QA Engineer'),
    ('IT Services and Consulting', 'DevOps Engineer'), ('IT Services and Consulting', 'Business Analyst'),
    ('Fintech', 'Risk Analyst'), ('Banking and Financial Services', 'Relationship Manager'),
    ('Banking and Financial Services', 'Accountant'), ('Manufacturing', 'Production Supervisor'),
    ('Manufacturing', 'Machine Operator'), ('Retail and E-commerce', 'Store Associate'),
    ('Retail and E-commerce', 'Delivery Executive'), ('Healthcare', 'Staff Nurse'),
    ('Education', 'Teacher'), ('Logistics and Transportation', 'Warehouse Associate'),
    ('Logistics and Transportation', 'Driver'), ('Hospitality', 'Front Office Executive'),
    ('Media and Creative Services', 'Photographer'), ('Media and Creative Services', 'Graphic Designer')
) AS v(industry, role)
JOIN mst.industry i ON i.english_name = v.industry;

-- A few UI labels to prove the translation path end to end.
INSERT INTO mst.ui_label (label_key, description) VALUES
    ('job.apply.button', 'Primary button on a job detail page.'),
    ('profile.save.button', 'Save button on the profile editor.');

INSERT INTO mst.ui_label_translation (ui_label_id, language_id, label_text)
SELECT k.id, l.id, v.txt
FROM (VALUES
    ('job.apply.button', 'en', 'Apply now'),
    ('job.apply.button', 'hi', 'अभी आवेदन करें'),
    ('job.apply.button', 'kn', 'ಈಗ ಅರ್ಜಿ ಸಲ್ಲಿಸಿ'),
    ('profile.save.button', 'en', 'Save profile')
) AS v(label_key, iso, txt)
JOIN mst.ui_label k ON k.label_key = v.label_key
JOIN mst.language l ON l.iso_code = v.iso;

RESET ROLE;
