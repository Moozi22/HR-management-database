USE University_HR_ManagementSystem_Team_101;
GO
-- helper for j,k,l,n
IF OBJECT_ID('Get_Leave_Approvers', 'IF') IS NOT NULL DROP FUNCTION Get_Leave_Approvers;
GO
CREATE FUNCTION Get_Leave_Approvers
(
    @employee_ID INT,
    @start_date DATE,
    @end_date DATE
)
RETURNS @Approvers TABLE
(
    Approver_Type VARCHAR(50), -- e.g., 'UpperBoard', 'HR'
    Approver_ID INT
)
AS
BEGIN
    -- Variables to store employee info and calculated approvers
    DECLARE @emp_highest_rank INT;
    DECLARE @emp_dept_name VARCHAR(50);
    
    DECLARE @Approver1_ID INT; -- Upper Board
    DECLARE @Approver2_ID INT; -- HR
    
    DECLARE @Dean_ID INT;
    DECLARE @ViceDean_ID INT;

    -- 1. Fetch employee details (Department and Highest Rank)
    SELECT @emp_dept_name = dept_name
    FROM Employee
    WHERE employee_ID = @employee_ID;

    SELECT @emp_highest_rank = MIN(R.rank)
    FROM Employee_Role ER
    JOIN Role R ON ER.role_name = R.role_name
    WHERE ER.emp_ID = @employee_ID;

    -- ====================================================================
    -- 2. Determine Approver 2 (HR Approver - The Final Approver)
    -- ====================================================================

    IF @emp_dept_name = 'HR Department'
    BEGIN
        -- HR employees are approved by the HR Manager (Rank 3)
        SELECT @Approver2_ID = E.employee_ID
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        WHERE ER.role_name = 'HR Manager'; 
    END
    ELSE
    BEGIN
        -- Department-specific HR Representative (e.g., HR_Representative_MET)
        DECLARE @HR_Rep_RoleName VARCHAR(50) = 'HR_Representative_' + @emp_dept_name;
        SELECT @Approver2_ID = E.employee_ID
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        WHERE ER.role_name = @HR_Rep_RoleName;
    END

    -- ====================================================================
    -- 3. Determine Approver 1 (Upper Board - The First Approver)
    -- ====================================================================
    
    IF @emp_highest_rank <= 4 -- President, VP, Dean, Vice Dean, HR Manager/Rep
    BEGIN
        -- Approver is the President (Rank 1)
        SELECT @Approver1_ID = E.employee_ID
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        WHERE ER.role_name = 'President';
    END
    ELSE -- Rank 5 or 6 (Lecturer, TA, Medical Doctor, etc.)
    BEGIN
        -- Approver is Dean/Vice-Dean
        
        -- Find Dean ID
        SELECT @Dean_ID = E.employee_ID
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        WHERE ER.role_name = 'Dean' AND E.dept_name = @emp_dept_name;

        -- Find Vice Dean ID
        SELECT @ViceDean_ID = E.employee_ID
        FROM Employee E JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        WHERE ER.role_name = 'Vice Dean' AND E.dept_name = @emp_dept_name;

        -- Substitution Logic: Use Vice Dean if Dean is on leave
        IF dbo.Is_On_Leave(@Dean_ID, @start_date, @end_date) = 1
        BEGIN
            SET @Approver1_ID = @ViceDean_ID;
        END
        ELSE
        BEGIN
            SET @Approver1_ID = @Dean_ID;
        END
    END

    -- ====================================================================
    -- 4. Populate the return table
    -- ====================================================================

    -- Insert Upper Board Approver (First Approver)
    IF @Approver1_ID IS NOT NULL
    BEGIN
        INSERT INTO @Approvers (Approver_Type, Approver_ID)
        VALUES ('UpperBoard', @Approver1_ID);
    END
    
    -- Insert HR Approver (Final Approver)
    IF @Approver2_ID IS NOT NULL
    BEGIN
        INSERT INTO @Approvers (Approver_Type, Approver_ID)
        VALUES ('HR', @Approver2_ID);
    END

    RETURN;
END
GO
--todo check return ids in multivalued functions
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
IF OBJECT_ID('MyPerformance', 'IF') IS NOT NULL 
    DROP FUNCTION MyPerformance;
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
        performance_ID,
        rating,
        comments,
        semester,
        emp_ID
    FROM
        Performance
    WHERE
        emp_ID = @employee_ID
        AND semester = @semester
);
GO

-- 2.5.c: MyAttendance (Table Valued Function)
IF OBJECT_ID('MyAttendance', 'IF') IS NOT NULL 
    DROP FUNCTION MyAttendance;
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
        A.attendance_ID,
        A.date,
        A.check_in_time,
        A.check_out_time,
        A.total_duration, -- Computed column
        A.status,
        A.emp_ID
    FROM
        Attendance A
    INNER JOIN
        Employee E ON A.emp_ID = E.employee_ID
    WHERE
        A.emp_ID = @employee_ID
        -- Filter for the current month and year
        AND MONTH(A.date) = MONTH(GETDATE())
        AND YEAR(A.date) = YEAR(GETDATE())
        -- EXCLUSION Constraint: Must exclude the employee's unattended official day off.
        -- Unattended official day off means Status='Absent' AND the day matches official_day_off.
        AND NOT (
            A.status = 'Absent'
            AND DATENAME(dw, A.date) = E.official_day_off
        )
);
GO

-- 2.5.d: Last_month_payroll (Table Valued Function)
IF OBJECT_ID('Last_month_payroll', 'IF') IS NOT NULL 
    DROP FUNCTION Last_month_payroll;
GO

CREATE FUNCTION Last_month_payroll
(
    @employee_ID int
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        ID,
        payment_date,
        final_salary_amount,
        from_date,
        to_date,
        comments,
        bonus_amount,
        deductions_amount,
        emp_ID
    FROM
        Payroll
    WHERE
        emp_ID = @employee_ID
        -- Filter for the last month. 
        -- This logic identifies records where the payment_date falls in the previous calendar month.
        AND MONTH(payment_date) = MONTH(DATEADD(month, -1, GETDATE()))
        AND YEAR(payment_date) = YEAR(DATEADD(month, -1, GETDATE()))
);
GO

-- 2.5.e: Deductions_Attendance (Table Valued Function)
IF OBJECT_ID('Deductions_Attendance', 'IF') IS NOT NULL 
    DROP FUNCTION Deductions_Attendance;
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
        deduction_ID,
        emp_ID,
        date,
        amount,
        type,
        status,
        unpaid_ID,
        attendance_ID
    FROM
        Deduction
    WHERE
        emp_ID = @employee_ID
        AND MONTH(date) = @month
        AND YEAR(date) = YEAR(GETDATE()) -- Assuming 'current year' if month is input
        -- Constraint: Must be for attendance issues (missing_hours or missing_days)
        AND type IN ('missing_hours', 'missing_days')
);
GO

-- 2.5.f: Is_On_Leave (Function)
IF OBJECT_ID('Is_On_Leave', 'FN') IS NOT NULL 
    DROP FUNCTION Is_On_Leave;
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
        SELECT 1
        FROM Leave L
        JOIN (
            -- Correctly finding the request_IDs associated with the employee
            SELECT request_ID FROM Annual_Leave WHERE emp_ID = @employee_ID
            UNION ALL
            SELECT request_ID FROM Accidental_Leave WHERE emp_ID = @employee_ID
            UNION ALL
            SELECT request_ID FROM Medical_Leave WHERE emp_ID = @employee_ID
            UNION ALL
            SELECT request_ID FROM Unpaid_Leave WHERE emp_ID = @employee_ID
            UNION ALL
            SELECT request_ID FROM Compensation_Leave WHERE emp_ID = @employee_ID
        ) AS EmployeeLeaves ON L.request_ID = EmployeeLeaves.request_ID
        WHERE
            -- Check for date overlap (start1 <= end2 AND end1 >= start2)
            L.start_date <= @to_date
            AND L.end_date >= @from_date
            -- Constraint: Pending status must be treated as approved
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
    
    -- Note: Contract type and balance checks are omitted as per the project instruction: "Assume inputs are correct."
    
    DECLARE @RequestID int;

    -- 1. Insert into Leave (using the standard minimal Leave schema)
    INSERT INTO [Leave] (date_of_request, start_date, end_date, final_approval_status)
    VALUES (GETDATE(), @start_date, @end_date, 'pending');
    
    SET @RequestID = SCOPE_IDENTITY();

    -- 2. Insert into Annual_Leave
    INSERT INTO Annual_Leave (request_ID, emp_ID, replacement_emp)
    VALUES (@RequestID, @employee_ID, @replacement_emp);

    -- 3. Populate Approval Table (Employee_Approve_Leave)
    -- Uses the centralized helper function for ALL hierarchy logic.
    INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status)
    SELECT
        A.Approver_ID,
        @RequestID,
        'pending'
    FROM dbo.Get_Leave_Approvers(@employee_ID, @start_date, @end_date) A
    WHERE A.Approver_ID IS NOT NULL
    GROUP BY A.Approver_ID;
END
GO

-- 2.5.h: Status_le (Table Valued Function)
GO
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
    -- 1. Annual Leave status
    SELECT 
        L.request_ID,
        'Annual' AS Leave_Type,
        L.date_of_request,          -- Added date_of_request
        L.start_date, 
        L.end_date,
        L.num_days,                 -- Added num_days
        L.final_approval_status
    FROM Leave L
    JOIN Annual_Leave AL ON L.request_ID = AL.request_ID
    WHERE AL.emp_ID = @employee_ID                                  -- Filter by employee ID (via AL table)
      AND MONTH(L.date_of_request) = MONTH(GETDATE())               -- **FIXED**: Filter by submission date
      AND YEAR(L.date_of_request) = YEAR(GETDATE())                 -- **FIXED**: Filter by submission date
      
    UNION ALL
    
    -- 2. Accidental Leave status
    SELECT 
        L.request_ID,
        'Accidental' AS Leave_Type,
        L.date_of_request,          -- Added date_of_request
        L.start_date,
        L.end_date,
        L.num_days,                 -- Added num_days
        L.final_approval_status
    FROM Leave L
    JOIN Accidental_Leave ACL ON L.request_ID = ACL.request_ID
    WHERE ACL.emp_ID = @employee_ID                                 -- Filter by employee ID (via ACL table)
      AND MONTH(L.date_of_request) = MONTH(GETDATE())               -- **FIXED**: Filter by submission date
      AND YEAR(L.date_of_request) = YEAR(GETDATE())                 -- **FIXED**: Filter by submission date
);
GO

-- 2.5.i: Upperboard_approve_annual (Stored Procedure)
IF OBJECT_ID('Upperboard_approve_annual', 'P') IS NOT NULL DROP PROCEDURE Upperboard_approve_annual;
GO
CREATE PROCEDURE Upperboard_approve_annual
(
    @request_ID int,
    @Upperboard_ID int
    -- Removed @replacement_ID, as it must be fetched internally
)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Variables to fetch data internally and perform checks
    DECLARE @ReplacementID int;
    DECLARE @LeaveStartDate date;
    DECLARE @LeaveEndDate date;
    DECLARE @LeaveEmpDept varchar(50);
    DECLARE @RepEmpDept varchar(50);
    DECLARE @IsReplacementOnLeave bit;
    DECLARE @ApprovalStatus varchar(50) = 'rejected';

    -- 1. Fetch necessary details for checks (using correct joins: Leave -> Annual_Leave -> Employee)
    SELECT
        @ReplacementID = AL.replacement_emp,
        @LeaveStartDate = L.start_date,
        @LeaveEndDate = L.end_date,
        @LeaveEmpDept = E_Leave.dept_name
    FROM [Leave] L
    JOIN Annual_Leave AL ON L.request_ID = AL.request_ID
    JOIN Employee E_Leave ON AL.emp_ID = E_Leave.employee_ID
    WHERE L.request_ID = @request_ID;

    -- Proceed only if a replacement was actually specified in the submission
    IF @ReplacementID IS NOT NULL
    BEGIN
        -- 2. Check if replacement is on leave (using 2.5.f)
        SET @IsReplacementOnLeave = dbo.Is_On_Leave(@ReplacementID, @LeaveStartDate, @LeaveEndDate);

        -- 3. Get replacement's department
        SELECT @RepEmpDept = dept_name
        FROM Employee
        WHERE employee_ID = @ReplacementID;

        -- Approval condition: replacement isn’t on leave AND works in the same department
        IF ISNULL(@IsReplacementOnLeave, 0) = 0 AND @LeaveEmpDept = @RepEmpDept
        BEGIN
            SET @ApprovalStatus = 'approved';
        END
    END
    
    -- 4. Update Upperboard's approval status
    UPDATE Employee_Approve_Leave
    SET status = @ApprovalStatus
    WHERE Emp1_ID = @Upperboard_ID AND Leave_ID = @request_ID;

    -- 5. Final approval status update (Rejection cascade as per Q&A)
    IF @ApprovalStatus = 'rejected'
    BEGIN
        -- Update the final status of the leave
        UPDATE [Leave] SET final_approval_status = 'rejected' WHERE request_ID = @request_ID;
        
        -- Cascade the rejection to all other pending approvals
        UPDATE Employee_Approve_Leave
        SET status = 'rejected'
        WHERE Leave_ID = @request_ID
          AND status = 'pending';
    END
END
GO

-- 2.5.j: Submit_accidental (Stored Procedure)
IF OBJECT_ID('Submit_accidental', 'P') IS NOT NULL DROP PROCEDURE Submit_accidental;
GO
CREATE PROCEDURE Submit_accidental
    @employee_ID int,
    @start_date date,
    @end_date date
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Variable to store the generated request ID
    DECLARE @new_request_ID int;

    -- ====================================================================
    -- 1. Insert into Leave table
    -- ====================================================================

    INSERT INTO Leave (date_of_request, start_date, end_date, final_approval_status)
    VALUES (GETDATE(), @start_date, @end_date, 'pending');

    -- Get the newly generated request_ID
    SET @new_request_ID = SCOPE_IDENTITY();

    -- ====================================================================
    -- 2. Insert into Accidental_Leave table
    -- ====================================================================

    INSERT INTO Accidental_Leave (request_ID, emp_ID)
    VALUES (@new_request_ID, @employee_ID);

    -- ====================================================================
    -- 3. Populate Approval Hierarchy using the Helper Function
    -- ====================================================================

    -- Insert the required approvers (Upper Board and HR) into the hierarchy table.
    -- The helper function handles all the rank, department, and substitution logic.
    INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status)
    SELECT
        A.Approver_ID, 
        @new_request_ID, 
        'pending'
    FROM dbo.Get_Leave_Approvers(@employee_ID, @start_date, @end_date) A
    WHERE A.Approver_ID IS NOT NULL
    -- Ensures we only insert one row for each unique approver (usually 2 rows: UpperBoard and HR)
    GROUP BY A.Approver_ID; 

END
GO
GO


IF OBJECT_ID('Submit_medical', 'P') IS NOT NULL DROP PROCEDURE Submit_medical;
GO
CREATE PROCEDURE Submit_medical
    @employee_ID int,
    @start_date date,
    @end_date date,
    @type varchar(50),                         -- e.g., 'sick', 'maternity'
    @insurance_status bit,
    @disability_details varchar(50),
    @document_description varchar(50),
    @file_name varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Variables to store the generated request and document IDs
    DECLARE @new_request_ID int;
    DECLARE @new_document_ID int;

    -- ====================================================================
    -- 1. Insert into Leave table
    -- ====================================================================

    INSERT INTO Leave (date_of_request, start_date, end_date, final_approval_status)
    VALUES (GETDATE(), @start_date, @end_date, 'pending');

    -- Get the newly generated request_ID
    SET @new_request_ID = SCOPE_IDENTITY();

    -- ====================================================================
    -- 2. Insert into Medical_Leave table
    -- ====================================================================

    INSERT INTO Medical_Leave (request_ID, insurance_status, disability_details, type, emp_ID)
    VALUES (@new_request_ID, @insurance_status, @disability_details, @type, @employee_ID);

    -- ====================================================================
    -- 3. Insert into Document table
    -- ====================================================================
    
    -- Medical documents are typically marked as 'Valid' upon submission
    INSERT INTO Document (type, description, file_name, creation_date, expiry_date, status, emp_ID, medical_ID)
    VALUES 
    (
        'Medical Leave Document',         -- type
        @document_description,             -- description
        @file_name,                        -- file_name
        GETDATE(),                         -- creation_date
        DATEADD(year, 1, GETDATE()),       -- assumed 1-year expiry date (can be adjusted)
        'Valid',                           -- status
        @employee_ID,                      -- emp_ID
        @new_request_ID                    -- medical_ID (FK to Medical_Leave/Leave)
    );

    -- ====================================================================
    -- 4. Populate Approval Hierarchy using the Helper Function
    -- ====================================================================

    -- Insert the required approvers (Upper Board and HR) into the hierarchy table.
    -- Note: Medical leaves, like Annual and Accidental, follow the standard rank-based hierarchy.
    INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status)
    SELECT
        A.Approver_ID, 
        @new_request_ID, 
        'pending'
    FROM dbo.Get_Leave_Approvers(@employee_ID, @start_date, @end_date) A
    WHERE A.Approver_ID IS NOT NULL
    GROUP BY A.Approver_ID; 

END
GO

-- 2.5.l
IF OBJECT_ID('Submit_unpaid', 'P') IS NOT NULL DROP PROCEDURE Submit_unpaid;
GO
CREATE PROCEDURE Submit_unpaid
    @employee_ID int,
    @start_date date,
    @end_date date,
    @document_description varchar(50),
    @file_name varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @new_request_ID int;

    INSERT INTO Leave (date_of_request, start_date, end_date, final_approval_status)
    VALUES (GETDATE(), @start_date, @end_date, 'pending');

    SET @new_request_ID = SCOPE_IDENTITY();

    
    INSERT INTO Unpaid_Leave (request_ID, emp_ID)
    VALUES (@new_request_ID, @employee_ID);

    INSERT INTO Document (type, description, file_name, creation_date, expiry_date, status, emp_ID, unpaid_ID)
    VALUES 
    (
        'Unpaid Leave Document',
        @document_description,
        @file_name,
        GETDATE(),
        DATEADD(year, 100, GETDATE()), 
        'Valid',
        @employee_ID,
        @new_request_ID
    );

    INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status)
    SELECT
        A.Approver_ID, 
        @new_request_ID, 
        'pending'
    FROM dbo.Get_Leave_Approvers(@employee_ID, @start_date, @end_date) A
    WHERE A.Approver_ID IS NOT NULL
    GROUP BY A.Approver_ID; 

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
    
    DECLARE @ApprovalStatus varchar(50) = 'rejected'; -- Default status is rejected

    -- 1. Check the approval rule: Is there a document submitted with a valid status?
    -- The Foreign Key (unpaid_ID) is on the Document table.
    IF EXISTS (
        SELECT 1 
        FROM Document D
        WHERE D.unpaid_ID = @request_ID -- Correct join on Document.unpaid_ID
          AND D.status = 'Valid'        -- Check for 'Valid' status as per requirement
    )
    BEGIN
        SET @ApprovalStatus = 'approved';
    END

    -- 2. Update Upperboard's approval status in the hierarchy table (Employee_Approve_Leave)
    -- This record must exist, so only UPDATE is necessary.
    UPDATE Employee_Approve_Leave 
    SET status = @ApprovalStatus 
    WHERE Emp1_ID = @Upperboard_ID 
      AND Leave_ID = @request_ID;

    -- 3. Final approval status update and rejection cascade (Q&A rule)
    IF @ApprovalStatus = 'rejected'
    BEGIN
        -- If the Upper Board rejects, the leave is globally rejected.
        
        -- A. Update the final status of the leave in the Leave super-type table
        UPDATE [Leave] 
        SET final_approval_status = 'rejected' 
        WHERE request_ID = @request_ID;
        
        -- B. Cascade the rejection to all other pending approvals (e.g., the HR approver)
        UPDATE Employee_Approve_Leave
        SET status = 'rejected'
        WHERE Leave_ID = @request_ID
          AND status = 'pending';
    END
    -- NOTE: If @ApprovalStatus is 'approved', final_approval_status remains 'pending'
    -- for HR to perform their checks.
END
GO

-- 2.5.n: Submit_compensation (Stored Procedure)
IF OBJECT_ID('Submit_compensation', 'P') IS NOT NULL DROP PROCEDURE Submit_compensation;
GO
CREATE PROCEDURE Submit_compensation
    @employee_ID int,
    @compensation_date date,
    @reason varchar(50),
    @date_of_original_workday date,
    @replacement_emp int
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @new_request_ID int;

    INSERT INTO Leave (date_of_request, start_date, end_date, final_approval_status)
    VALUES (GETDATE(), @compensation_date, @compensation_date, 'pending');

    SET @new_request_ID = SCOPE_IDENTITY();

    INSERT INTO Compensation_Leave (request_ID, reason, date_of_original_workday, emp_ID, replacement_emp)
    VALUES (@new_request_ID, @reason, @date_of_original_workday, @employee_ID, @replacement_emp);

    INSERT INTO Employee_Replace_Employee (Emp1_ID, Emp2_ID, from_date, to_date)
    VALUES (@employee_ID, @replacement_emp, @compensation_date, @compensation_date);

    INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status)
    SELECT
        A.Approver_ID, 
        @new_request_ID, 
        'pending'
   
    FROM dbo.Get_Leave_Approvers(@employee_ID, @compensation_date, @compensation_date) A
    WHERE A.Approver_ID IS NOT NULL
    GROUP BY A.Approver_ID; 

END
GO

-- 2.5.o: Dean_andHR_Evaluation (Stored Procedure)
IF OBJECT_ID('Dean_andHR_Evaluation', 'P') IS NOT NULL DROP PROCEDURE Dean_andHR_Evaluation;
GO
CREATE PROCEDURE Dean_andHR_Evaluation
    @employee_ID int, -- The employee being evaluated
    @rating int,
    @comment varchar(50),
    @semester char(3)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Performance (rating, comments, semester, emp_ID)
    VALUES (@rating, @comment, @semester, @employee_ID);
END
GO