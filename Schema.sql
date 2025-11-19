CREATE DATABASE University_HR_ManagementSystem_Team_101;

GO
USE University_HR_ManagementSystem_Team_101;
GO


CREATE PROCEDURE createAllTables
AS
BEGIN

    CREATE TABLE Department (
        name varchar(50) PRIMARY KEY,
        building_location varchar(50)
    );

  
    CREATE TABLE Role (
        role_name varchar(50) PRIMARY KEY,
        title varchar(50),
        description varchar(50),
        rank int,
        base_salary decimal(10,2),
        percentage_YOE decimal(4,2),
        percentage_overtime decimal(4,2),
        annual_balance int,
        accidental_balance int
    );

  
    CREATE TABLE Employee (
        employee_ID int IDENTITY(1,1) PRIMARY KEY,
        first_name varchar(50),
        last_name varchar(50),
        email varchar(50),
        password varchar(50),
        address varchar(50),
        gender char(1),
        official_day_off varchar(50),
        years_of_experience int,
        national_ID char(16),
        employment_status varchar(50),
        type_of_contract varchar(50),
        emergency_contact_name varchar(50),
        emergency_contact_phone char(11),
        annual_balance int,
        accidental_balance int,
        salary decimal(10,2),
        hire_date date,
        last_working_date date,
        dept_name varchar(50),
        FOREIGN KEY (dept_name) REFERENCES Department(name),
        check(type_of_contract in ('full_time','part_time')),
        check(employment_status in ('active','onleave','notice_period','resigned'))
    );

 
    CREATE TABLE Employee_Phone (
        emp_ID int,
        phone_num char(11),
        PRIMARY KEY (emp_ID, phone_num),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID)
    );

   
    CREATE TABLE Role_existsIn_Department (
        department_name varchar(50),
        role_name varchar(50),
        PRIMARY KEY (department_name, role_name),
        FOREIGN KEY (department_name) REFERENCES Department(name),
        FOREIGN KEY (role_name) REFERENCES Role(role_name)
    );

  
    CREATE TABLE Employee_Role (
        emp_ID int,
        role_name varchar(50),
        PRIMARY KEY (emp_ID, role_name),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (role_name) REFERENCES Role(role_name)
    );


    CREATE TABLE Leave (
        request_ID int IDENTITY(1,1) PRIMARY KEY,
        date_of_request date,
        start_date date,
        end_date date,
        num_days AS DATEDIFF(day, start_date, end_date),
        final_approval_status varchar(50) default 'pending',
        check (final_approval_status in ('approved','rejected','pending'))
    );

   
    CREATE TABLE Annual_Leave (
        request_ID int PRIMARY KEY,
        emp_ID int,
        replacement_emp int,
        FOREIGN KEY (request_ID) REFERENCES Leave(request_ID),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (replacement_emp) REFERENCES Employee(employee_ID)
    );

 
    CREATE TABLE Accidental_Leave (
        request_ID int PRIMARY KEY,
        emp_ID int,
        FOREIGN KEY (request_ID) REFERENCES Leave(request_ID),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID)
    );

  
    CREATE TABLE Medical_Leave (
        request_ID int PRIMARY KEY,
        insurance_status bit,
        disability_details varchar(50),
        type varchar(50),
        emp_ID int,
        FOREIGN KEY (request_ID) REFERENCES Leave(request_ID),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        check (type in ('sick','maternity'))
    );


    CREATE TABLE Unpaid_Leave (
        request_ID int PRIMARY KEY,
        emp_ID int,
        FOREIGN KEY (request_ID) REFERENCES Leave(request_ID),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID)
    );

  
    CREATE TABLE Compensation_Leave (
        request_ID int PRIMARY KEY,
        reason varchar(50),
        date_of_original_workday date,
        emp_ID int,
        replacement_emp int,
        FOREIGN KEY (request_ID) REFERENCES Leave(request_ID),
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (replacement_emp) REFERENCES Employee(employee_ID)
    );


    CREATE TABLE Document (
        document_ID int IDENTITY(1,1) PRIMARY KEY,
        type varchar(50),
        description varchar(50),
        file_name varchar(50),
        creation_date date,
        expiry_date date,
        status varchar(50),
        emp_ID int,
        medical_ID int,
        unpaid_ID int,
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (medical_ID) REFERENCES Medical_Leave(request_ID),
        FOREIGN KEY (unpaid_ID) REFERENCES Unpaid_Leave(request_ID),
        check(status in ('Valid','Expired'))
    );

  
    CREATE TABLE Attendance (
        attendance_ID int IDENTITY(1,1) PRIMARY KEY,
        date date,
        check_in_time time,
        check_out_time time,
        total_duration AS DATEDIFF(minute, check_in_time, check_out_time),
        status varchar(50) default 'Absent',
        emp_ID int,
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        check(status in ('Attended','Absent'))
    );

   
    CREATE TABLE Deduction (
        deduction_ID int IDENTITY(1,1) PRIMARY KEY,
        emp_ID int,
        [date] date,
        amount decimal(10,2),
        type varchar(50),
        status varchar(50) default 'Pending',
        unpaid_ID int,
        attendance_ID int,
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (unpaid_ID) REFERENCES Unpaid_Leave(request_ID),
        FOREIGN KEY (attendance_ID) REFERENCES Attendance(attendance_ID),
        check(type in ('unpaid','missing_hours','missing_days')),
        check(status in ('finalized','pending'))
    );


    CREATE TABLE Payroll (
        ID int IDENTITY(1,1) PRIMARY KEY,
        payment_date date,
        final_salary_amount decimal(10,2),
        from_date date,
        to_date date,
        comments varchar(150),
        bonus_amount decimal(10,2),
        deductions_amount decimal(10,2),
        emp_ID int,
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID)
    );

  
    CREATE TABLE Performance (
        performance_ID int IDENTITY(1,1) PRIMARY KEY,
        rating int,
        comments varchar(50),
        semester char(3),
        emp_ID int,
        FOREIGN KEY (emp_ID) REFERENCES Employee(employee_ID),
        check (rating between 1 and 5)
    );

   
    CREATE TABLE Employee_Replace_Employee (
        Emp1_ID int,
        Emp2_ID int,
        from_date date,
        to_date date,
        PRIMARY KEY (Emp1_ID, Emp2_ID, from_date),
        FOREIGN KEY (Emp1_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (Emp2_ID) REFERENCES Employee(employee_ID)
    );

   
    CREATE TABLE Employee_Approve_Leave (
        Emp1_ID int,
        Leave_ID int,
        status varchar(50),
        PRIMARY KEY (Emp1_ID, Leave_ID),
        FOREIGN KEY (Emp1_ID) REFERENCES Employee(employee_ID),
        FOREIGN KEY (Leave_ID) REFERENCES Leave(request_ID)
    );
END;
GO


CREATE PROCEDURE dropAllTables
AS
BEGIN
    DROP TABLE Employee_Approve_Leave;
    DROP TABLE Employee_Replace_Employee;
    DROP TABLE Performance;
    DROP TABLE Payroll;
    DROP TABLE Deduction;
    DROP TABLE Attendance;
    DROP TABLE Document;
    DROP TABLE Compensation_Leave;
    DROP TABLE Unpaid_Leave;
    DROP TABLE Medical_Leave;
    DROP TABLE Accidental_Leave;
    DROP TABLE Annual_Leave;
    DROP TABLE Leave;
    DROP TABLE Employee_Role;
    DROP TABLE Role_existsIn_Department;
    DROP TABLE Employee_Phone;
    DROP TABLE Employee;
    DROP TABLE Role;
    DROP TABLE Department;
END;
GO


CREATE PROCEDURE clearAllTables
AS
BEGIN
    DELETE FROM Employee_Approve_Leave;
    DELETE FROM Employee_Replace_Employee;
    DELETE FROM Performance;
    DELETE FROM Payroll;
    DELETE FROM Deduction;
    DELETE FROM Attendance;
    DELETE FROM Document;
    DELETE FROM Compensation_Leave;
    DELETE FROM Unpaid_Leave;
    DELETE FROM Medical_Leave;
    DELETE FROM Accidental_Leave;
    DELETE FROM Annual_Leave;
    DELETE FROM Leave;
    DELETE FROM Employee_Role;
    DELETE FROM Role_existsIn_Department;
    DELETE FROM Employee_Phone;
    DELETE FROM Employee;
    DELETE FROM Role;
    DELETE FROM Department;
END;
GO

CREATE PROCEDURE dropAllProceduresFunctionsViews
AS
BEGIN
    -- DROP VIEWS (from 2.2)
    DROP VIEW IF EXISTS allEmployeeProfiles;
    DROP VIEW IF EXISTS NoEmployeeDept;
    DROP VIEW IF EXISTS allPerformance;
    DROP VIEW IF EXISTS allRejectedMedicals;
    DROP VIEW IF EXISTS allEmployeeAttendance;

    -- DROP FUNCTIONS (from 2.4 & 2.5)
    DROP FUNCTION IF EXISTS HRLoginValidation;
    DROP FUNCTION IF EXISTS Is_On_Leave;
    DROP FUNCTION IF EXISTS Bonus_amount;
    DROP FUNCTION IF EXISTS Find_Employee_Leave_History;

    -- DROP PROCEDURES (from 2.1, 2.3, 2.4, 2.5)
    -- Section 2.1 Basic Procedures
    DROP PROCEDURE IF EXISTS createAllTables;
    DROP PROCEDURE IF EXISTS dropAllTables;
    DROP PROCEDURE IF EXISTS clearAllTables;

    -- Section 2.3 & 2.5 (The rest of the required procedures)
    DROP PROCEDURE IF EXISTS Upperboard_approve_unpaids;
    DROP PROCEDURE IF EXISTS Dean_andHR_Evaluation;
    DROP PROCEDURE IF EXISTS Submit_annual;
    DROP PROCEDURE IF EXISTS Submit_accidental;
    DROP PROCEDURE IF EXISTS Submit_medical;
    DROP PROCEDURE IF EXISTS Submit_compensation;
    DROP PROCEDURE IF EXISTS HR_Update_Doc;
    DROP PROCEDURE IF EXISTS HR_Remove_Deductions;
END;
GO
createAllTables;

