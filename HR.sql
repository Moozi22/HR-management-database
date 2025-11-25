USE University_HR_ManagementSystem_Team_101;
GO

-- 2.4.a
USE University_HR_ManagementSystem;
GO

IF OBJECT_ID('HRLoginValidation', 'FN') IS NOT NULL DROP FUNCTION HRLoginValidation;
GO

CREATE FUNCTION HRLoginValidation
(
    @employee_ID int,
    @password varchar(50)
)
RETURNS bit
AS
BEGIN
    DECLARE @IsHR bit = 0;

    IF EXISTS (
        SELECT 1
        FROM Employee E
        JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        JOIN Role R ON ER.role_name = R.role_name
        WHERE E.employee_ID = @employee_ID
          AND E.password = @password 
          AND R.role_name LIKE 'HR%' 
    )
    BEGIN
        SET @IsHR = 1;
    END

    RETURN @IsHR;
END
GO

-- 2.4.h
IF OBJECT_ID('Bonus_amount') IS NOT NULL DROP FUNCTION Bonus_amount;
GO

CREATE FUNCTION Bonus_amount
(
    @employee_ID INT
)
RETURNS DECIMAL(10, 2)
AS
BEGIN
    DECLARE @EmployeeSalary DECIMAL(10, 2);
    DECLARE @StandardHourlyRate DECIMAL(10, 2);
    DECLARE @OTRate DECIMAL(10, 2); -- Overtime Rate (1.5x)
    DECLARE @TotalOTMinutes INT = 0;
    DECLARE @BonusValue DECIMAL(10, 2) = 0.00;
    
    DECLARE @CurrentDate DATE = CAST(GETDATE() AS DATE);
    DECLARE @FirstDayOfMonth DATE = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);
    DECLARE @RequiredDailyMinutes INT = 480; -- 8 hours

    -- 1. Fetch Salary
    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;
    
    IF @EmployeeSalary IS NULL OR @EmployeeSalary <= 0
        RETURN 0.00;

    -- 2. Calculate Standard and Overtime Hourly Rates
    -- Standard Hourly Rate = (Salary / 22 days) / 8 hours
    SET @StandardHourlyRate = (@EmployeeSalary / 22.0) / 8.0;
    SET @OTRate = @StandardHourlyRate * 1.5;

    -- 3. Calculate Total Overtime Minutes for the current month
    -- We sum the excess duration (total_duration - 480) only for days > 8 hours
    SELECT @TotalOTMinutes = ISNULL(SUM(A.total_duration - @RequiredDailyMinutes), 0)
    FROM Attendance A
    WHERE A.emp_ID = @employee_ID
      AND A.date BETWEEN @FirstDayOfMonth AND @CurrentDate
      AND A.status = 'Attended'
      AND A.total_duration > @RequiredDailyMinutes;

    -- 4. Calculate Final Bonus Value
    IF @TotalOTMinutes > 0
    BEGIN
        -- Convert minutes to hours (using 60.0 for decimal division) and multiply by OT Rate
        SET @BonusValue = (@TotalOTMinutes / 60.0) * @OTRate;
    END

    RETURN @BonusValue;
END
GO

-- 2.4.b
IF OBJECT_ID('HR_approval_an_acc', 'P') IS NOT NULL DROP PROCEDURE HR_approval_an_acc;
GO

CREATE PROCEDURE HR_approval_an_acc
(
    @request_ID int,
    @HR_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmpID int;
    DECLARE @NumDays int = 0;
    DECLARE @LeaveType varchar(50);
    DECLARE @RequiredBalance int;
    DECLARE @HRStatus varchar(50);
    SELECT @EmpID = AL.emp_ID, 
           @NumDays = L.num_days
    FROM Leave L 
    JOIN Annual_Leave AL ON L.request_ID = AL.request_ID 
    WHERE L.request_ID = @request_ID;
    
    IF @EmpID IS NOT NULL
        SET @LeaveType = 'Annual';
    ELSE
    BEGIN
        SELECT @EmpID = ACL.emp_ID, 
               @NumDays = L.num_days
        FROM Leave L 
        JOIN Accidental_Leave ACL ON L.request_ID = ACL.request_ID 
        WHERE L.request_ID = @request_ID;
        IF @EmpID IS NOT NULL
            SET @LeaveType = 'Accidental';
    END

    IF @EmpID IS NULL
    BEGIN
        PRINT 'ERROR: Invalid request ID or not an Annual/Accidental leave.';
        RETURN;
    END

    SELECT @RequiredBalance = CASE WHEN @LeaveType = 'Annual' THEN annual_balance ELSE accidental_balance END
    FROM Employee 
    WHERE employee_ID = @EmpID;

    IF @NumDays > 0 AND @NumDays <= @RequiredBalance
        SET @HRStatus = 'approved';

    IF EXISTS (SELECT 1 FROM Employee_Approve_Leave WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave 
        SET status = @HRStatus
        WHERE Emp1_ID = @HR_ID 
          AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@HR_ID, @request_ID, @HRStatus);
    END
    
    IF EXISTS (
        SELECT 1 FROM Employee_Approve_Leave 
        WHERE Leave_ID = @request_ID 
          AND status = 'rejected'
    )
    BEGIN
        UPDATE Leave 
        SET final_approval_status = 'rejected' 
        WHERE request_ID = @request_ID;
        PRINT 'Leave request ' + CAST(@request_ID AS VARCHAR(10)) + ' rejected due to insufficient balance or higher authority rejection.';
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM Employee_Approve_Leave 
        WHERE Leave_ID = @request_ID 
          AND status IN ('pending', 'rejected') 
    )
    BEGIN
        -- Final Approval
        UPDATE Leave 
        SET final_approval_status = 'approved' 
        WHERE request_ID = @request_ID;
        
        -- Deduct balance
        IF @LeaveType = 'Annual'
            UPDATE Employee SET annual_balance = annual_balance - @NumDays WHERE employee_ID = @EmpID;
        ELSE IF @LeaveType = 'Accidental'
            UPDATE Employee SET accidental_balance = accidental_balance - @NumDays WHERE employee_ID = @EmpID;
        
        PRINT 'Leave request ' + CAST(@request_ID AS VARCHAR(10)) + ' finally approved. ' + CAST(@NumDays AS VARCHAR(5)) + ' days deducted.';
    END
    ELSE
    BEGIN
        PRINT 'HR completed approval check (' + @HRStatus + '). Final approval status remains PENDING, waiting for other approvers.';
    END
END
GO

-- 2.4.c
IF OBJECT_ID('HR_approval_unpaid', 'P') IS NOT NULL DROP PROCEDURE HR_approval_unpaid;
GO

CREATE PROCEDURE HR_approval_unpaid
(
    @request_ID int,
    @HR_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmpID int;
    DECLARE @NumDays int;
    DECLARE @HRStatus varchar(50) = 'approved'; -- Assume approval unless a rule fails

    -- 1. Fetch data
    SELECT @EmpID = UL.emp_ID, 
           @NumDays = L.num_days
    FROM Leave L 
    JOIN Unpaid_Leave UL ON L.request_ID = UL.request_ID
    WHERE L.request_ID = @request_ID;

    IF @EmpID IS NULL
    BEGIN
        -- Invalid ID case
        SET @HRStatus = 'rejected';
    END
    ELSE
    BEGIN
        -- 2. HR Rule Check 1: Max Duration (Max 30 days per request)
        IF @NumDays > 30
        BEGIN
            SET @HRStatus = 'rejected';
        END

        -- 3. HR Rule Check 2: Valid Memo Document (CRITICAL MISSING CHECK)
        IF @HRStatus = 'approved' AND NOT EXISTS (
            SELECT 1
            FROM Document
            WHERE unpaid_ID = @request_ID
              AND status = 'Valid'
        )
        BEGIN
            SET @HRStatus = 'rejected';
        END
    END
    
    -- 4. Update HR's Status in Approval Hierarchy
    IF EXISTS (SELECT 1 FROM Employee_Approve_Leave WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave SET status = @HRStatus 
        WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@HR_ID, @request_ID, @HRStatus);
    END
    
    -- 5. Check for Rejection Cascade (Rule: Rejected by anyone rejects the final request)
    IF EXISTS (
        SELECT 1 FROM Employee_Approve_Leave 
        WHERE Leave_ID = @request_ID 
          AND status = 'rejected'
    )
    BEGIN
        UPDATE Leave 
        SET final_approval_status = 'rejected' 
        WHERE request_ID = @request_ID;
        PRINT 'Leave request ' + CAST(@request_ID AS VARCHAR(10)) + ' rejected due to failing HR rules or higher authority rejection.';
        RETURN;
    END

    -- 6. Check for Final Approval (Rule: All must approve)
    -- If NO approver is pending or rejected, then it is approved.
    IF NOT EXISTS (
        SELECT 1 FROM Employee_Approve_Leave 
        WHERE Leave_ID = @request_ID 
          AND status IN ('pending')
    )
    BEGIN
        UPDATE Leave 
        SET final_approval_status = 'approved' 
        WHERE request_ID = @request_ID;
        PRINT 'Unpaid leave request ' + CAST(@request_ID AS VARCHAR(10)) + ' finally approved.';
    END
    ELSE
    BEGIN
        PRINT 'HR completed approval check (' + @HRStatus + '). Final approval status remains PENDING, waiting for Upper Board.';
    END
END
GO

-- 2.4.d
IF OBJECT_ID('HR_approval_comp', 'P') IS NOT NULL DROP PROCEDURE HR_approval_comp;
GO

CREATE PROCEDURE HR_approval_comp
(
    @request_ID int,
    @HR_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmpID int;
    DECLARE @OriginalWorkday date;
    DECLARE @LeaveDate date;
    DECLARE @AttendanceDuration int; 
    DECLARE @HRStatus varchar(50) = 'approved'; -- Assume approval unless a rule fails

    -- 1. Fetch data
    SELECT @EmpID = CL.emp_ID, 
           @OriginalWorkday = CL.date_of_original_workday,
           @LeaveDate = L.start_date 
    FROM Compensation_Leave CL
    JOIN Leave L ON CL.request_ID = L.request_ID
    WHERE CL.request_ID = @request_ID;

    IF @EmpID IS NULL
    BEGIN
        SET @HRStatus = 'rejected';
    END
    ELSE
    BEGIN
        -- 2. HR Rule Check 1: Same Month Rule
        IF MONTH(@LeaveDate) <> MONTH(@OriginalWorkday) OR YEAR(@LeaveDate) <> YEAR(@OriginalWorkday)
        BEGIN
            SET @HRStatus = 'rejected';
        END

        -- 3. HR Rule Check 2: 8-Hour Workday Check (only if Rule 1 passed)
        IF @HRStatus = 'approved'
        BEGIN
            SELECT @AttendanceDuration = total_duration -- total_duration is a computed column
            FROM Attendance
            WHERE emp_ID = @EmpID
              AND date = @OriginalWorkday;

            -- 480 minutes = 8 hours
            IF ISNULL(@AttendanceDuration, 0) < 480 
            BEGIN
                SET @HRStatus = 'rejected';
            END
        END
    END

    -- 4. Update HR's Status in Approval Hierarchy
    IF EXISTS (SELECT 1 FROM Employee_Approve_Leave WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave 
        SET status = @HRStatus
        WHERE Emp1_ID = @HR_ID 
          AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@HR_ID, @request_ID, @HRStatus);
    END
    
    -- 5. Check for Rejection Cascade
    IF EXISTS (
        SELECT 1 FROM Employee_Approve_Leave 
        WHERE Leave_ID = @request_ID 
          AND status = 'rejected'
    )
    BEGIN
        UPDATE Leave 
        SET final_approval_status = 'rejected' 
        WHERE request_ID = @request_ID;
        PRINT 'Compensation leave request ' + CAST(@request_ID AS VARCHAR(10)) + ' rejected due to failing HR rules or higher authority rejection.';
        RETURN;
    END

    -- 6. Check for Final Approval (All must approve)
    IF NOT EXISTS (
        SELECT 1 FROM Employee_Approve_Leave 
        WHERE Leave_ID = @request_ID 
          AND status = 'pending'
    )
    BEGIN
        UPDATE Leave 
        SET final_approval_status = 'approved' 
        WHERE request_ID = @request_ID;
        PRINT 'Compensation leave request ' + CAST(@request_ID AS VARCHAR(10)) + ' finally approved.';
    END
    ELSE
    BEGIN
        PRINT 'HR completed approval check (' + @HRStatus + '). Final approval status remains PENDING, waiting for other approvers.';
    END
END
GO

-- 2.4.e
IF OBJECT_ID('Deduction_hours', 'P') IS NOT NULL DROP PROCEDURE Deduction_hours;
GO

CREATE PROCEDURE Deduction_hours
(
    @employee_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @RatePerHour decimal(10,2);
    DECLARE @CurrentDate date = CAST(GETDATE() AS date);
    DECLARE @FirstDayOfMonth date = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);
    
    DECLARE @TotalActualMinutes int;
    DECLARE @TotalScheduledMinutes int;
    DECLARE @MissingMinutes int;
    DECLARE @DeductionAmount decimal(10,2);

    -- 1. Fetch Salary and Calculate Hourly Rate
    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;
    IF @EmployeeSalary IS NULL OR @EmployeeSalary <= 0
    BEGIN
        PRINT 'ERROR: Employee not found or salary is zero/null. No deduction calculated.';
        RETURN;
    END

    -- Hourly Rate: (Salary / 22 working days) / 8 hours per day
    SET @RatePerHour = (@EmployeeSalary / 22.0) / 8.0;

    -- 2. Calculate Total Actual Minutes vs Total Scheduled Minutes for Attended Days
    SELECT 
        @TotalActualMinutes = ISNULL(SUM(A.total_duration), 0),
        @TotalScheduledMinutes = COUNT(A.attendance_ID) * 480 -- 480 minutes = 8 hours
    FROM Attendance A
    WHERE A.emp_ID = @employee_ID
      AND A.date BETWEEN @FirstDayOfMonth AND @CurrentDate
      AND A.status = 'Attended';

    -- 3. Calculate Missing Minutes (The overall deficit)
    SET @MissingMinutes = @TotalScheduledMinutes - @TotalActualMinutes;

    IF @MissingMinutes > 0
    BEGIN
        SET @DeductionAmount = (@MissingMinutes / 60.0) * @RatePerHour;
        INSERT INTO Deduction (emp_ID, date, amount, type, status)
        VALUES (@employee_ID, @CurrentDate, @DeductionAmount, 'missing_hours', 'Pending');

        PRINT 'Deduction for ' + CAST(@MissingMinutes / 60.0 AS VARCHAR(10)) + ' missing hours created for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + ' in the amount of ' + CAST(@DeductionAmount AS VARCHAR(10)) + '.';
    END
    ELSE
    BEGIN
        PRINT 'No deduction for missing hours required for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + ' this month.';
    END
END
GO

-- 2.4.f
IF OBJECT_ID('Deduction_days', 'P') IS NOT NULL DROP PROCEDURE Deduction_days;
GO

CREATE PROCEDURE Deduction_days
(
    @employee_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @DailyRate decimal(10,2);
    DECLARE @OfficialDayOff varchar(10);
    DECLARE @CurrentDate date = CAST(GETDATE() AS date);
    DECLARE @FirstDayOfMonth date = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);

    -- 1. Fetch Salary and Official Day Off
    SELECT @EmployeeSalary = E.salary, @OfficialDayOff = E.official_day_off 
    FROM Employee E 
    WHERE E.employee_ID = @employee_ID;

    IF @EmployeeSalary IS NULL OR @EmployeeSalary <= 0
    BEGIN
        PRINT 'ERROR: Employee not found or salary is zero/null. No deduction calculated.';
        RETURN;
    END

    -- 2. Calculate Daily Rate (based on 22 working days)
    SET @DailyRate = @EmployeeSalary / 22.0;

    -- 3. Insert deductions for each 'Absent' day that is NOT a day off
    INSERT INTO Deduction (emp_ID, date, amount, type, attendance_ID, status)
    SELECT 
        @employee_ID, 
        A.date, 
        @DailyRate,
        'missing_day',
        A.attendance_ID,
        'Pending'
    FROM Attendance A
    WHERE A.emp_ID = @employee_ID
      AND A.date BETWEEN @FirstDayOfMonth AND @CurrentDate
      AND A.status = 'Absent'
      AND DATENAME(dw, A.date) <> @OfficialDayOff 
      -- Ensure this deduction hasn't already been created
      AND A.attendance_ID NOT IN (SELECT attendance_ID FROM Deduction WHERE type = 'missing_day');

    IF @@ROWCOUNT > 0
    BEGIN
        PRINT CAST(@@ROWCOUNT AS VARCHAR(5)) + ' deductions for missing days created for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + '.';
    END
    ELSE
    BEGIN
        PRINT 'No new deductions for missing days required for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + ' this month.';
    END
END
GO

-- 2.4.g
IF OBJECT_ID('Deduction_unpaid', 'P') IS NOT NULL DROP PROCEDURE Deduction_unpaid;
GO

CREATE PROCEDURE Deduction_unpaid
(
    @employee_ID int
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @DailyRate decimal(10,2);
    DECLARE @RowsAffected int;

    -- 1. Fetch Salary and Calculate Daily Rate
    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;

    IF @EmployeeSalary IS NULL OR @EmployeeSalary <= 0
    BEGIN
        PRINT 'ERROR: Employee not found or salary is zero/null. No deduction calculated.';
        RETURN;
    END

    SET @DailyRate = @EmployeeSalary / 22.0;

    -- 2. Insert deductions for all *approved* Unpaid Leaves that do not yet have a deduction
    INSERT INTO Deduction (emp_ID, date, amount, type, leave_ID, status)
    SELECT
        @employee_ID, 
        CAST(GETDATE() AS date), -- Deduction date is the current date
        L.num_days * @DailyRate, -- Amount = num_days * Daily Rate
        'unpaid_leave',
        L.request_ID,
        'Pending'
    FROM Leave L
    JOIN Unpaid_Leave UL ON L.request_ID = UL.request_ID
    WHERE UL.emp_ID = @employee_ID
      AND L.final_approval_status = 'approved'
      -- Ensure the deduction hasn't been created yet for this specific leave request
      AND L.request_ID NOT IN (SELECT leave_ID FROM Deduction WHERE type = 'unpaid_leave');

    SET @RowsAffected = @@ROWCOUNT;

    IF @RowsAffected > 0
    BEGIN
        PRINT CAST(@RowsAffected AS VARCHAR(5)) + ' deductions for approved unpaid leave requests created for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + '.';
    END
    ELSE
    BEGIN
        PRINT 'No new deductions for approved unpaid leave required for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + '.';
    END
END
GO

-- 2.4.i
IF OBJECT_ID('Add_Payroll', 'P') IS NOT NULL DROP PROCEDURE Add_Payroll;
GO

CREATE PROCEDURE Add_Payroll
(
    @employee_ID INT,
    @from_date DATE,
    @to_date DATE
)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Variables for Salary Calculation 
    DECLARE @BaseSalary DECIMAL(10, 2);
    DECLARE @YOE INT;
    DECLARE @PercentageYOE DECIMAL(5, 2);
    
    DECLARE @TotalSalary DECIMAL(10, 2); -- The standing calculated salary
    DECLARE @TotalDeductions DECIMAL(10, 2);
    DECLARE @TotalBonus DECIMAL(10, 2);
    DECLARE @FinalNetSalary DECIMAL(10, 2);

    -- 1. CRITICAL: Check for existing payroll record (Missing in your version)
    IF EXISTS (
        SELECT 1 
        FROM Payroll 
        WHERE emp_ID = @employee_ID 
          AND from_date = @from_date 
          AND to_date = @to_date
    )
    BEGIN
        PRINT 'WARNING: Payroll for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + ' for this period already exists. Skipping insertion.';
        RETURN;
    END

    -- 2. CRITICAL: Calculate Standing Salary Inline (Correctly using the formula)
    SELECT TOP 1
        @BaseSalary = R.base_salary,
        @YOE = E.years_of_experience,
        @PercentageYOE = R.percentage_YOE
    FROM Employee E
    JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
    JOIN Role R ON ER.role_name = R.role_name
    WHERE E.employee_ID = @employee_ID
    ORDER BY R.rank ASC; 

    IF @BaseSalary IS NULL OR @BaseSalary <= 0
    BEGIN
        PRINT 'ERROR: Employee ' + CAST(@employee_ID AS VARCHAR(10)) + ' not found or base salary is zero. Payroll generation aborted.';
        RETURN;
    END

    -- Salary = base_salary + (%year_of_experience/100) * years_of_experience * base_salary
    SET @TotalSalary = @BaseSalary + ((@PercentageYOE / 100.0) * @YOE * @BaseSalary);

    -- 3. Sum up Deductions for the month (Pending status)
    SELECT @TotalDeductions = ISNULL(SUM(amount), 0.00)
    FROM Deduction
    WHERE emp_ID = @employee_ID
      AND date BETWEEN @from_date AND @to_date
      AND status = 'Pending';
    
    -- 4. Calculate Total Bonus using the required function 2.4.h
    SET @TotalBonus = dbo.Bonus_amount(@employee_ID);

    -- 5. Calculate Final Net Salary
    SET @FinalNetSalary = @TotalSalary - @TotalDeductions + @TotalBonus;

    -- 6. Insert into Payroll
    INSERT INTO Payroll (payment_date, final_salary_amount, from_date, to_date, comments, bonus_amount, deductions_amount, emp_ID)
    VALUES (
        CAST(GETDATE() AS DATE), 
        @FinalNetSalary,
        @from_date,
        @to_date,
        'Monthly Payroll Generated',
        @TotalBonus,
        @TotalDeductions,
        @employee_ID
    );

    -- 7. Finalize Deductions
    UPDATE Deduction
    SET status = 'Finalized'
    WHERE emp_ID = @employee_ID
      AND date BETWEEN @from_date AND @to_date
      AND status = 'Pending';

    PRINT 'Payroll generated successfully for Employee ' + CAST(@employee_ID AS VARCHAR(10)) + 
          ' (Net: ' + CAST(@FinalNetSalary AS VARCHAR(20)) + ').';
END
GO