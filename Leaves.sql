USE University_HR_ManagementSystem_Team_101;
GO

---------------------------------------------------------------------------------
-- Helper Logic for Leave Approval Hierarchy (Refactored to remove TOP 1)
---------------------------------------------------------------------------------

-- This function determines the Dean/Vice-Dean or HR Manager who should be the first approver.
IF OBJECT_ID('GetFirstApproverID', 'FN') IS NOT NULL DROP FUNCTION GetFirstApproverID;
GO
CREATE FUNCTION GetFirstApproverID
(
    @employee_ID int
)
RETURNS int
AS
BEGIN
    DECLARE @ApproverID int;
    DECLARE @EmpDept varchar(50);
    
    SELECT @EmpDept = E.dept_name
    FROM Employee E
    WHERE E.employee_ID = @employee_ID;

    IF @EmpDept = 'HR Department'
    BEGIN
        -- Find the HR Manager with the highest years_of_experience (using MIN(ID) to pick one arbitrarily)
        SELECT @ApproverID = MIN(E.employee_ID)
        FROM Employee E
        JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        JOIN Role R ON ER.role_name = R.role_name
        WHERE R.title = 'HR Manager'
          AND E.employment_status = 'active'
          AND E.years_of_experience = (
              SELECT MAX(E2.years_of_experience)
              FROM Employee E2
              JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID
              JOIN Role R2 ON ER2.role_name = R2.role_name
              WHERE R2.title = 'HR Manager'
                AND E2.employment_status = 'active'
          );
    END
    ELSE
    BEGIN
        -- 1. Try to find the Dean (Highest YOE among active Deans in department)
        SELECT @ApproverID = MIN(E.employee_ID)
        FROM Employee E
        JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        JOIN Role R ON ER.role_name = R.role_name
        WHERE R.title = 'Dean'
          AND E.dept_name = @EmpDept
          AND E.employment_status = 'active'
          AND E.years_of_experience = (
              SELECT MAX(E2.years_of_experience)
              FROM Employee E2
              JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID
              JOIN Role R2 ON ER2.role_name = R2.role_name
              WHERE R2.title = 'Dean'
                AND E2.dept_name = @EmpDept
                AND E2.employment_status = 'active'
          );
        
        -- 2. If no active Dean found, check for active Vice Dean (Highest YOE)
        IF @ApproverID IS NULL
        BEGIN
             SELECT @ApproverID = MIN(E.employee_ID)
             FROM Employee E
             JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
             JOIN Role R ON ER.role_name = R.role_name
             WHERE R.title = 'Vice Dean'
               AND E.dept_name = @EmpDept
               AND E.employment_status = 'active'
               AND E.years_of_experience = (
                   SELECT MAX(E2.years_of_experience)
                   FROM Employee E2
                   JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID
                   JOIN Role R2 ON ER2.role_name = R2.role_name
                   WHERE R2.title = 'Vice Dean'
                     AND E2.dept_name = @EmpDept
                     AND E2.employment_status = 'active'
               );
        END
    END
    
    RETURN @ApproverID;
END
GO

-- This function finds the HR employee (HR Representative or HR Manager) who is the final approver.
IF OBJECT_ID('GetFinalApproverID', 'FN') IS NOT NULL DROP FUNCTION GetFinalApproverID;
GO
CREATE FUNCTION GetFinalApproverID
(
    @employee_ID int
)
RETURNS int
AS
BEGIN
    DECLARE @FinalApproverID int;
    DECLARE @EmpDept varchar(50);
    
    SELECT @EmpDept = E.dept_name
    FROM Employee E
    WHERE E.employee_ID = @employee_ID;
    
    -- If employee is HR, the HR Manager is the final approver (Highest YOE among active HR Managers).
    IF @EmpDept = 'HR Department'
    BEGIN
        SELECT @FinalApproverID = MIN(E.employee_ID)
        FROM Employee E
        JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        JOIN Role R ON ER.role_name = R.role_name
        WHERE R.title = 'HR Manager'
          AND E.employment_status = 'active'
          AND E.years_of_experience = (
              SELECT MAX(E2.years_of_experience)
              FROM Employee E2
              JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID
              JOIN Role R2 ON ER2.role_name = R2.role_name
              WHERE R2.title = 'HR Manager'
                AND E2.employment_status = 'active'
          );
    END
    ELSE
    BEGIN
        -- Otherwise, the HR Representative for that department's area (Highest YOE among active HR Reps).
        SELECT @FinalApproverID = MIN(E.employee_ID)
        FROM Employee E
        JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        JOIN Role R ON ER.role_name = R.role_name
        WHERE R.title LIKE 'HR Representative%' 
          AND R.role_name LIKE '%' + @EmpDept
          AND E.employment_status = 'active'
          AND E.years_of_experience = (
              SELECT MAX(E2.years_of_experience)
              FROM Employee E2
              JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID
              JOIN Role R2 ON ER2.role_name = R2.role_name
              WHERE R2.title LIKE 'HR Representative%' 
                AND R2.role_name LIKE '%' + @EmpDept
                AND E2.employment_status = 'active'
          );
    END

    RETURN @FinalApproverID;
END
GO

---------------------------------------------------------------------------------
-- 2.5 As an Employee I should be able to:
---------------------------------------------------------------------------------

-- 2.5.a: EmployeeLoginValidation (Function)
IF OBJECT_ID('EmployeeLoginValidation', 'FN') IS NOT NULL DROP FUNCTION EmployeeLoginValidation;
GO
CREATE FUNCTION EmployeeLoginValidation
(
    @employee_ID int,
    @password varchar(50)
)
RETURNS bit
AS
BEGIN
    DECLARE @Success bit = 0;

    IF EXISTS (
        SELECT * FROM Employee 
        WHERE employee_ID = @employee_ID
          AND password = @password
    )
    BEGIN
        SET @Success = 1;
    END

    RETURN @Success;
END
GO

-- 2.5.b: MyPerformance (Table Valued Function)
IF OBJECT_ID('MyPerformance', 'IF') IS NOT NULL DROP FUNCTION MyPerformance;
GO
CREATE FUNCTION MyPerformance
(
    @employee_ID int,
    @semester char(3)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        P.rating,
        P.comment,
        P.semester
    FROM Performance P
    WHERE P.emp_ID = @employee_ID
      AND P.semester = @semester
);
GO

-- 2.5.c: MyAttendance (Table Valued Function)
IF OBJECT_ID('MyAttendance', 'IF') IS NOT NULL DROP FUNCTION MyAttendance;
GO
CREATE FUNCTION MyAttendance
(
    @employee_ID int
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        A.[date],
        A.check_in_time,
        A.check_out_time,
        A.total_duration,
        A.status
    FROM Attendance A
    JOIN Employee E ON A.emp_ID = E.employee_ID
    WHERE A.emp_ID = @employee_ID
      AND MONTH(A.[date]) = MONTH(GETDATE())
      AND YEAR(A.[date]) = YEAR(GETDATE())
      -- Exclude unattended official day off
      AND NOT (A.[status] = 'absent' AND DATENAME(weekday, A.[date]) = E.official_day_off)
);
GO

-- 2.5.d: Last_month_payroll (Table Valued Function)
IF OBJECT_ID('Last_month_payroll', 'IF') IS NOT NULL DROP FUNCTION Last_month_payroll;
GO
CREATE FUNCTION Last_month_payroll
(
    @employee_ID int
)
RETURNS TABLE
AS
RETURN
(
    -- Find the date range for the last calendar month
    WITH LastMonth AS (
        SELECT 
            DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 1, 0) AS StartDate,
            DATEADD(day, -1, DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)) AS EndDate
    )
    
    SELECT 
        P.payment_date,
        P.final_salary_amount,
        P.from_date,
        P.to_date,
        P.bonus_amount,
        P.deductions_amount
    FROM Payroll P
    JOIN LastMonth LM ON 1=1
    WHERE P.emp_ID = @employee_ID
      AND P.from_date = LM.StartDate
      AND P.to_date = LM.EndDate
);
GO

-- 2.5.e: Deductions_Attendance (Table Valued Function)
IF OBJECT_ID('Deductions_Attendance', 'IF') IS NOT NULL DROP FUNCTION Deductions_Attendance;
GO
CREATE FUNCTION Deductions_Attendance
(
    @employee_ID int,
    @month int
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        D.[date],
        D.amount,
        D.type,
        D.[status]
    FROM Deduction D
    WHERE D.emp_ID = @employee_ID
      AND MONTH(D.[date]) = @month
      AND YEAR(D.[date]) = YEAR(GETDATE())
      AND D.type IN ('missing_hours', 'missing_days')
);
GO

-- 2.5.f: Is_On_Leave (Function)
IF OBJECT_ID('Is_On_Leave', 'FN') IS NOT NULL DROP FUNCTION Is_On_Leave;
GO
CREATE FUNCTION Is_On_Leave
(
    @employee_ID int,
    @from_date date,
    @to_date date
)
RETURNS bit
AS
BEGIN
    DECLARE @IsOnLeave bit = 0;

    IF EXISTS (
        SELECT * FROM [Leave] L
        WHERE L.emp_ID = @employee_ID
          -- Check for overlap with the specified period
          AND L.start_date <= @to_date
          AND L.end_date >= @from_date
          -- Treat pending as approved for verification purposes
          AND L.final_approval_status IN ('approved', 'pending')
    )
    BEGIN
        SET @IsOnLeave = 1;
    END

    RETURN @IsOnLeave;
END
GO


-- 2.5.g: Submit_annual (Stored Procedure)
IF OBJECT_ID('Submit_annual', 'P') IS NOT NULL DROP PROCEDURE Submit_annual;
GO
CREATE PROCEDURE Submit_annual
(
    @employee_ID int,
    @replacement_emp int,
    @start_date date,
    @end_date date
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NumDays int = DATEDIFF(day, @start_date, @end_date) + 1;
    DECLARE @ContractType varchar(50);
    DECLARE @RequestID int;
    DECLARE @FirstApprover int;
    DECLARE @FinalApprover int;

    SELECT @ContractType = type_of_contract 
    FROM Employee 
    WHERE employee_ID = @employee_ID;

    -- Part-time employees are not eligible for annual leave
    IF @ContractType = 'part_time'
    BEGIN
        RETURN;
    END

    -- 1. Insert into Leave
    INSERT INTO [Leave] (emp_ID, start_date, end_date, num_days, final_approval_status)
    VALUES (@employee_ID, @start_date, @end_date, @NumDays, 'pending');
    SET @RequestID = SCOPE_IDENTITY();

    -- 2. Insert into Annual_Leave
    INSERT INTO Annual_Leave (request_ID, emp_ID, replacement_emp)
    VALUES (@RequestID, @employee_ID, @replacement_emp);

    -- 3. Populate Approval Table (Employee_Approve_Leave)
    
    -- Special Rule: Dean/Vice-Dean annual leave request
    IF EXISTS (
        SELECT * FROM Employee_Role ER JOIN Role R ON ER.role_name = R.role_name
        WHERE ER.emp_ID = @employee_ID AND R.title IN ('Dean', 'Vice Dean')
    )
    BEGIN
        -- Approvers: President and HR Representative
        DECLARE @PresidentID int;
        DECLARE @HRRepID int;

        -- Find President (Highest YOE) - Refactored to avoid TOP 1
        SELECT @PresidentID = MIN(E.employee_ID) 
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID JOIN Role R ON ER.role_name = R.role_name 
        WHERE R.title = 'President'
        AND E.years_of_experience = (SELECT MAX(E2.years_of_experience) FROM Employee E2 JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID JOIN Role R2 ON ER2.role_name = R2.role_name WHERE R2.title = 'President');
        
        -- Find HR Representative (Highest YOE) - Refactored to avoid TOP 1
        SELECT @HRRepID = MIN(E.employee_ID) 
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID JOIN Role R ON ER.role_name = R.role_name 
        WHERE R.title LIKE 'HR Representative%'
        AND E.years_of_experience = (SELECT MAX(E2.years_of_experience) FROM Employee E2 JOIN Employee_Role ER2 ON E2.employee_ID = ER2.emp_ID JOIN Role R2 ON ER2.role_name = R2.role_name WHERE R2.title LIKE 'HR Representative%');


        IF @PresidentID IS NOT NULL
            INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@PresidentID, @RequestID, 'pending');
        IF @HRRepID IS NOT NULL
            INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@HRRepID, @RequestID, 'pending');

    END
    ELSE -- Regular Employee Hierarchy
    BEGIN
        SET @FirstApprover = dbo.GetFirstApproverID(@employee_ID);
        SET @FinalApprover = dbo.GetFinalApproverID(@employee_ID);
        
        -- First Approver (Dean/HR Manager)
        IF @FirstApprover IS NOT NULL
            INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FirstApprover, @RequestID, 'pending');
        
        -- Final Approver (HR Employee)
        IF @FinalApprover IS NOT NULL
            INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FinalApprover, @RequestID, 'pending');
    END
END
GO

-- 2.5.h: Status_le (Table Valued Function)
IF OBJECT_ID('Status_le', 'IF') IS NOT NULL DROP FUNCTION Status_le;
GO
CREATE FUNCTION Status_le
(
    @employee_ID int
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        L.request_ID,
        L.start_date,
        L.end_date,
        L.final_approval_status,
        'Annual' AS LeaveType
    FROM [Leave] L
    JOIN Annual_Leave AL ON L.request_ID = AL.request_ID
    WHERE L.emp_ID = @employee_ID
      AND MONTH(L.start_date) = MONTH(GETDATE())
      AND YEAR(L.start_date) = YEAR(GETDATE())
      
    UNION ALL
    
    SELECT 
        L.request_ID,
        L.start_date,
        L.end_date,
        L.final_approval_status,
        'Accidental' AS LeaveType
    FROM [Leave] L
    JOIN Accidental_Leave ACL ON L.request_ID = ACL.request_ID
    WHERE L.emp_ID = @employee_ID
      AND MONTH(L.start_date) = MONTH(GETDATE())
      AND YEAR(L.start_date) = YEAR(GETDATE())
);
GO

-- 2.5.i: Upperboard_approve_annual (Stored Procedure)
IF OBJECT_ID('Upperboard_approve_annual', 'P') IS NOT NULL DROP PROCEDURE Upperboard_approve_annual;
GO
CREATE PROCEDURE Upperboard_approve_annual
(
    @request_ID int,
    @Upperboard_ID int,
    @replacement_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @LeaveEmpDept varchar(50);
    DECLARE @RepEmpDept varchar(50);
    DECLARE @IsReplacementOnLeave bit;
    DECLARE @ApprovalStatus varchar(50) = 'rejected';

    -- 1. Check if replacement is on leave (using 2.5.f)
    SELECT @IsReplacementOnLeave = dbo.Is_On_Leave(@replacement_ID, L.start_date, L.end_date)
    FROM [Leave] L
    WHERE L.request_ID = @request_ID;

    -- 2. Check if replacement works in the same department
    SELECT @LeaveEmpDept = E.dept_name
    FROM [Leave] L JOIN Employee E ON L.emp_ID = E.employee_ID
    WHERE L.request_ID = @request_ID;

    SELECT @RepEmpDept = dept_name
    FROM Employee 
    WHERE employee_ID = @replacement_ID;

    -- Approval condition: replacement isn’t on leave AND works in the same department
    IF ISNULL(@IsReplacementOnLeave, 0) = 0 AND @LeaveEmpDept = @RepEmpDept
    BEGIN
        SET @ApprovalStatus = 'approved';
    END

    -- 3. Update Upperboard's approval status
    IF EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Emp1_ID = @Upperboard_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave 
        SET status = @ApprovalStatus 
        WHERE Emp1_ID = @Upperboard_ID AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@Upperboard_ID, @request_ID, @ApprovalStatus);
    END

    -- 4. Final approval status update (handled by 2.4.b logic, but included here for completeness/rejection cascade)
    IF @ApprovalStatus = 'rejected' OR EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Leave_ID = @request_ID AND status = 'rejected')
    BEGIN
        UPDATE [Leave] SET final_approval_status = 'rejected' WHERE request_ID = @request_ID;
    END
END
GO


-- 2.5.j: Submit_accidental (Stored Procedure)
IF OBJECT_ID('Submit_accidental', 'P') IS NOT NULL DROP PROCEDURE Submit_accidental;
GO
CREATE PROCEDURE Submit_accidental
(
    @employee_ID int,
    @start_date date,
    @end_date date
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NumDays int = DATEDIFF(day, @start_date, @end_date) + 1;
    DECLARE @RequestID int;
    DECLARE @FirstApprover int;
    DECLARE @FinalApprover int;

    -- Accidental leaves duration is only 1 day per leave
    IF @NumDays != 1
    BEGIN
        -- Request rejected immediately
        RETURN;
    END

    -- 1. Insert into Leave
    INSERT INTO [Leave] (emp_ID, start_date, end_date, num_days, final_approval_status)
    VALUES (@employee_ID, @start_date, @end_date, @NumDays, 'pending');
    SET @RequestID = SCOPE_IDENTITY();

    -- 2. Insert into Accidental_Leave
    INSERT INTO Accidental_Leave (request_ID, emp_ID)
    VALUES (@RequestID, @employee_ID);

    -- 3. Populate Approval Table
    SET @FirstApprover = dbo.GetFirstApproverID(@employee_ID);
    SET @FinalApprover = dbo.GetFinalApproverID(@employee_ID);
    
    -- Approvers: First Approver (Dean/HR Manager) and Final Approver (HR Employee)
    IF @FirstApprover IS NOT NULL
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FirstApprover, @RequestID, 'pending');
    
    IF @FinalApprover IS NOT NULL
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FinalApprover, @RequestID, 'pending');
END
GO


-- 2.5.k: Submit_medical (Stored Procedure)
IF OBJECT_ID('Submit_medical', 'P') IS NOT NULL DROP PROCEDURE Submit_medical;
GO
CREATE PROCEDURE Submit_medical
(
    @employee_ID int,
    @start_date date,
    @end_date date,
    @type varchar(50),
    @insurance_status bit,
    @disability_details varchar(50),
    @document_description varchar(50),
    @file_path varchar(50) -- Assuming file is a path/reference
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NumDays int = DATEDIFF(day, @start_date, @end_date) + 1;
    DECLARE @ContractType varchar(50);
    DECLARE @RequestID int;
    DECLARE @DocumentID int;
    DECLARE @FirstApprover int;
    DECLARE @FinalApprover int;

    SELECT @ContractType = type_of_contract 
    FROM Employee 
    WHERE employee_ID = @employee_ID;

    -- Part-time employees are not eligible for maternity leaves
    IF @ContractType = 'part_time' AND @type = 'maternity'
    BEGIN
        RETURN;
    END

    -- 1. Insert into Document
    INSERT INTO Document (description, file_path, upload_date, expiry_date, status)
    VALUES (@document_description, @file_path, GETDATE(), DATEADD(year, 1, GETDATE()), 'valid'); 
    SET @DocumentID = SCOPE_IDENTITY();

    -- 2. Insert into Leave
    INSERT INTO [Leave] (emp_ID, start_date, end_date, num_days, final_approval_status)
    VALUES (@employee_ID, @start_date, @end_date, @NumDays, 'pending');
    SET @RequestID = SCOPE_IDENTITY();

    -- 3. Insert into Medical_Leave
    INSERT INTO Medical_Leave (request_ID, emp_ID, type, insurance_status, disability_details, document_ID)
    VALUES (@RequestID, @employee_ID, @type, @insurance_status, @disability_details, @DocumentID);

    -- 4. Populate Approval Table
    SET @FirstApprover = dbo.GetFirstApproverID(@employee_ID);
    SET @FinalApprover = dbo.GetFinalApproverID(@employee_ID);
    
    -- Approvers: First Approver (Dean/HR Manager) and Final Approver (HR Employee)
    IF @FirstApprover IS NOT NULL
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FirstApprover, @RequestID, 'pending');
    
    IF @FinalApprover IS NOT NULL
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FinalApprover, @RequestID, 'pending');
END
GO

-- 2.5.m: Upperboard_approve_unpaids (Stored Procedure)
IF OBJECT_ID('Upperboard_approve_unpaids', 'P') IS NOT NULL DROP PROCEDURE Upperboard_approve_unpaids;
GO
CREATE PROCEDURE Upperboard_approve_unpaids
(
    @request_ID int,
    @Upperboard_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @HasValidMemo bit = 0;
    DECLARE @ApprovalStatus varchar(50) = 'rejected';

    -- Check if a memo document is submitted with a valid status
    IF EXISTS (
        SELECT * FROM Unpaid_Leave UL
        JOIN Document D ON UL.document_ID = D.document_ID
        WHERE UL.request_ID = @request_ID
          AND D.status = 'valid' -- Valid document status implies valid reason for this logic
    )
    BEGIN
        SET @HasValidMemo = 1;
    END

    IF @HasValidMemo = 1
    BEGIN
        SET @ApprovalStatus = 'approved';
    END

    -- 1. Update Upperboard's approval status
    IF EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Emp1_ID = @Upperboard_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave 
        SET status = @ApprovalStatus 
        WHERE Emp1_ID = @Upperboard_ID AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@Upperboard_ID, @request_ID, @ApprovalStatus);
    END

    -- 2. Final approval status update (Deductions are NOT reflected in this query)
    IF @ApprovalStatus = 'rejected' OR EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Leave_ID = @request_ID AND status = 'rejected')
    BEGIN
        UPDATE [Leave] SET final_approval_status = 'rejected' WHERE request_ID = @request_ID;
    END
    ELSE IF @ApprovalStatus = 'approved'
    BEGIN
        UPDATE [Leave] SET final_approval_status = 'approved' WHERE request_ID = @request_ID;
    END
END
GO


-- 2.5.n: Submit_compensation (Stored Procedure)
IF OBJECT_ID('Submit_compensation', 'P') IS NOT NULL DROP PROCEDURE Submit_compensation;
GO
CREATE PROCEDURE Submit_compensation
(
    @employee_ID int,
    @compensation_date date,
    @reason varchar(50),
    @date_of_original_workday date,
    @replacement_emp int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NumDays int = 1; -- Compensation leave is typically 1 day
    DECLARE @RequestID int;
    DECLARE @FinalApprover int;

    -- Compensation has to be requested within the same month
    IF MONTH(@compensation_date) != MONTH(@date_of_original_workday) OR YEAR(@compensation_date) != YEAR(@date_of_original_workday)
    BEGIN
        RETURN;
    END

    -- 1. Insert into Leave
    INSERT INTO [Leave] (emp_ID, start_date, end_date, num_days, final_approval_status)
    VALUES (@employee_ID, @compensation_date, @compensation_date, @NumDays, 'pending');
    SET @RequestID = SCOPE_IDENTITY();

    -- 2. Insert into Compensation_Leave
    INSERT INTO Compensation_Leave (request_ID, emp_ID, compensation_date, reason, date_of_original_workday, replacement_emp)
    VALUES (@RequestID, @employee_ID, @compensation_date, @reason, @date_of_original_workday, @replacement_emp);

    -- 3. Populate Approval Table
    SET @FinalApprover = dbo.GetFinalApproverID(@employee_ID);
    
    -- Final Approver (HR Employee)
    IF @FinalApprover IS NOT NULL
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) VALUES (@FinalApprover, @RequestID, 'pending');
END
GO


-- 2.5.o: Dean_andHR_Evaluation (Stored Procedure)
IF OBJECT_ID('Dean_andHR_Evaluation', 'P') IS NOT NULL DROP PROCEDURE Dean_andHR_Evaluation;
GO
CREATE PROCEDURE Dean_andHR_Evaluation
(
    @employee_ID int,
    @rating int,
    @comment varchar(50),
    @semester char(3)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Rating in performance should be from 1 to 5
    IF @rating < 1 OR @rating > 5
    BEGIN
        RETURN;
    END

    -- Insert into Performance table
    INSERT INTO Performance (emp_ID, rating, comment, semester)
    VALUES (@employee_ID, @rating, @comment, @semester);
END
GO