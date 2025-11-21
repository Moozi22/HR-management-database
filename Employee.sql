USE University_HR_ManagementSystem_Team_101;
GO
CREATE VIEW allEmployeeProfiles AS
SELECT 
    employee_ID,
    first_name,
    last_name,
    gender,
    email,
    address,
    years_of_experience,
    official_day_off,
    type_of_contract,
    employment_status,
    annual_balance,
    accidental_balance
FROM Employee;
go

CREATE VIEW NoEmployeeDept AS
SELECT 
    D.name AS department_name,
    D.building_location,
    COUNT(E.employee_ID) AS number_of_employees
FROM Department D
LEFT JOIN Employee E ON D.name = E.dept_name
GROUP BY 
    D.name,
    D.building_location;

    go

CREATE VIEW allPerformance AS
SELECT 
    performance_ID,
    emp_ID,
    rating,
    comments,
    semester
FROM Performance
WHERE semester LIKE 'W%';

go
CREATE VIEW allRejectedMedicals AS
SELECT
    ML.request_ID,
    ML.emp_ID,
    ML.insurance_status,
    ML.disability_details,
    ML.type,
    L.date_of_request,
    L.startdate,
    L.end_date,
    L.final_approval_status
FROM Medical_Leave ML
JOIN Leave L ON ML.request_ID = L.request_ID
WHERE L.final_approval_status = 'rejected';

go
CREATE VIEW allEmployeeAttendance AS
SELECT
    attendance_ID,
    emp_ID,
    date,
    check_in_time,
    check_out_time,
    total_duration,
    status
FROM Attendance
WHERE date = CAST(GETDATE() - 1 AS DATE);
