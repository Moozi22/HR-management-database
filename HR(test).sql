USE University_HR_ManagementSystem_Team_101;
GO

-- 2.4.a
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
        SELECT * FROM Employee E
        JOIN Employee_Role ER ON E.employee_ID = ER.emp_ID
        JOIN Role R ON ER.role_name = R.role_name
        WHERE E.employee_ID = @employee_ID
          AND E.password = @password 
          AND R.title IN ('HR Manager', 'HR Representative') 
    )
    BEGIN
        SET @IsHR = 1;
    END

    RETURN @IsHR;
END
GO


-- 2.4.h
IF OBJECT_ID('Bonus_amount', 'FN') IS NOT NULL DROP FUNCTION Bonus_amount;
GO
CREATE FUNCTION Bonus_amount
(
    @employee_ID int
)
RETURNS decimal(10,2)
AS
BEGIN
    DECLARE @BonusAmount decimal(10,2) = 0.00;
    DECLARE @TotalExtraMinutes int = 0;
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @OvertimeFactor decimal(4,2); 
    DECLARE @RatePerHour decimal(10,2);
    DECLARE @RequiredDailyMinutes int = 480; 
    
    DECLARE @CurrentDate date = CAST(GETDATE() AS date);
    DECLARE @from_date date = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);
    DECLARE @to_date date = DATEADD(day, -1, DATEADD(month, 1, @from_date));

    SELECT @EmployeeSalary = salary
    FROM Employee
    WHERE employee_ID = @employee_ID;
    
    SELECT @OvertimeFactor = MAX(R.percentage_overtime)
    FROM Employee_Role ER
    JOIN Role R ON ER.role_name = R.role_name
    WHERE ER.emp_ID = @employee_ID;

    SELECT @TotalExtraMinutes = ISNULL(SUM(CASE WHEN total_duration > @RequiredDailyMinutes THEN total_duration - @RequiredDailyMinutes ELSE 0 END), 0)
    FROM Attendance
    WHERE emp_ID = @employee_ID
      AND [date] BETWEEN @from_date AND @to_date
      AND [status] = 'Attended';

    IF @EmployeeSalary IS NOT NULL AND @EmployeeSalary > 0
    BEGIN
        SET @RatePerHour = (@EmployeeSalary / 22.0) / 8.0;
        SET @BonusAmount = @RatePerHour * ( (ISNULL(@OvertimeFactor, 0.0) / 100.0) * (@TotalExtraMinutes / 60.0) );
    END

    RETURN ISNULL(@BonusAmount, 0.00);
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
    DECLARE @ApprovalStatus varchar(50) = 'rejected';

    SELECT @EmpID = UL.emp_ID, @NumDays = L.num_days
    FROM Leave L JOIN Annual_Leave UL ON L.request_ID = UL.request_ID WHERE L.request_ID = @request_ID;
    
    IF @EmpID IS NOT NULL
        SET @LeaveType = 'Annual';
    ELSE
    BEGIN
        SELECT @EmpID = UL.emp_ID, @NumDays = L.num_days
        FROM Leave L JOIN Accidental_Leave UL ON L.request_ID = UL.request_ID WHERE L.request_ID = @request_ID;
        IF @EmpID IS NOT NULL
            SET @LeaveType = 'Accidental';
    END

    IF @EmpID IS NOT NULL
    BEGIN
        SELECT @RequiredBalance = CASE WHEN @LeaveType = 'Annual' THEN annual_balance ELSE accidental_balance END
        FROM Employee 
        WHERE employee_ID = @EmpID;

        IF @NumDays > 0 AND @NumDays <= @RequiredBalance
            SET @ApprovalStatus = 'approved';
    END

    IF EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave SET status = @ApprovalStatus 
        WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@HR_ID, @request_ID, @ApprovalStatus);
    END

    IF @ApprovalStatus = 'rejected' OR EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Leave_ID = @request_ID AND status = 'rejected')
    BEGIN
        UPDATE Leave SET final_approval_status = 'rejected' WHERE request_ID = @request_ID;
    END
    ELSE IF @ApprovalStatus = 'approved' AND @EmpID IS NOT NULL
    BEGIN
        UPDATE Leave SET final_approval_status = 'approved' 
        WHERE request_ID = @request_ID;
    END
    
    IF @ApprovalStatus = 'approved' AND EXISTS (SELECT * FROM Leave WHERE request_ID = @request_ID AND final_approval_status = 'approved')
    BEGIN
        IF @LeaveType = 'Annual'
            UPDATE Employee SET annual_balance = annual_balance - @NumDays WHERE employee_ID = @EmpID;
        ELSE IF @LeaveType = 'Accidental'
            UPDATE Employee SET accidental_balance = accidental_balance - @NumDays WHERE employee_ID = @EmpID;
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
    DECLARE @TotalApprovedUnpaidDaysThisYear int;
    DECLARE @CurrentYear int = YEAR(GETDATE());
    DECLARE @ApprovalStatus varchar(50) = 'approved'; 

    SELECT @EmpID = UL.emp_ID, @NumDays = L.num_days
    FROM Leave L JOIN Unpaid_Leave UL ON L.request_ID = UL.request_ID
    WHERE L.request_ID = @request_ID;

    IF @EmpID IS NULL 
    BEGIN
        SET @ApprovalStatus = 'rejected';
    END
    ELSE 
    BEGIN
        SELECT @TotalApprovedUnpaidDaysThisYear = ISNULL(SUM(L.num_days), 0)
        FROM Leave L JOIN Unpaid_Leave UL ON L.request_ID = UL.request_ID
        WHERE UL.emp_ID = @EmpID
          AND L.final_approval_status = 'approved'
          AND YEAR(L.start_date) = @CurrentYear
          AND L.request_ID != @request_ID;

        IF (@TotalApprovedUnpaidDaysThisYear + @NumDays) > 30
        BEGIN
            SET @ApprovalStatus = 'rejected';
        END

        IF @ApprovalStatus = 'approved' AND EXISTS (
            SELECT * FROM Leave L JOIN Unpaid_Leave UL ON L.request_ID = UL.request_ID
            WHERE UL.emp_ID = @EmpID 
              AND L.final_approval_status = 'approved'
              AND YEAR(L.start_date) = @CurrentYear
              AND L.request_ID != @request_ID 
        )
        BEGIN
            IF @NumDays > 0 
            BEGIN
                SET @ApprovalStatus = 'rejected';
            END
        END
    END
    
    IF EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave SET status = @ApprovalStatus 
        WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@HR_ID, @request_ID, @ApprovalStatus);
    END

    IF @ApprovalStatus = 'rejected' OR EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Leave_ID = @request_ID AND status = 'rejected')
    BEGIN
        UPDATE Leave SET final_approval_status = 'rejected' WHERE request_ID = @request_ID;
    END
    ELSE IF @ApprovalStatus = 'approved'
    BEGIN
        UPDATE Leave SET final_approval_status = 'approved' WHERE request_ID = @request_ID;
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
    DECLARE @ApprovalStatus varchar(50) = 'rejected';

    SELECT @EmpID = CL.emp_ID, 
           @OriginalWorkday = CL.date_of_original_workday,
           @LeaveDate = L.start_date 
    FROM Compensation_Leave CL
    JOIN Leave L ON CL.request_ID = L.request_ID
    WHERE CL.request_ID = @request_ID;
    
    IF @EmpID IS NOT NULL 
    BEGIN
        IF MONTH(@LeaveDate) = MONTH(@OriginalWorkday) AND YEAR(@LeaveDate) = YEAR(@OriginalWorkday)
        BEGIN
            SELECT @AttendanceDuration = total_duration
            FROM Attendance
            WHERE emp_ID = @EmpID
              AND [date] = @OriginalWorkday;

            IF ISNULL(@AttendanceDuration, 0) >= 480
            BEGIN
                SET @ApprovalStatus = 'approved';
            END
        END
    END

    IF EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID)
    BEGIN
        UPDATE Employee_Approve_Leave SET status = @ApprovalStatus 
        WHERE Emp1_ID = @HR_ID AND Leave_ID = @request_ID;
    END
    ELSE
    BEGIN
        INSERT INTO Employee_Approve_Leave (Emp1_ID, Leave_ID, status) 
        VALUES (@HR_ID, @request_ID, @ApprovalStatus);
    END

    IF @ApprovalStatus = 'rejected' OR EXISTS (SELECT * FROM Employee_Approve_Leave WHERE Leave_ID = @request_ID AND status = 'rejected')
    BEGIN
        UPDATE Leave SET final_approval_status = 'rejected' WHERE request_ID = @request_ID;
    END
    ELSE IF @ApprovalStatus = 'approved'
    BEGIN
        UPDATE Leave SET final_approval_status = 'approved' WHERE request_ID = @request_ID;
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
    DECLARE @RatePerHour decimal(10,2);
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @AttendanceID int;
    DECLARE @TotalDurationMinutes int;
    DECLARE @DeductionAmount decimal(10,2);
    DECLARE @RequiredDailyMinutes int = 480; 
    DECLARE @CurrentDate date = CAST(GETDATE() AS date);
    DECLARE @FirstDayOfMonth date = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);

    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;
    IF @EmployeeSalary IS NOT NULL AND @EmployeeSalary > 0
    BEGIN
        SET @RatePerHour = (@EmployeeSalary / 22.0) / 8.0;
    END
    ELSE
    BEGIN
        RETURN;
    END

    SELECT TOP 1 
        @AttendanceID = attendance_ID, 
        @TotalDurationMinutes = total_duration
    FROM Attendance
    WHERE emp_ID = @employee_ID
      AND [date] BETWEEN @FirstDayOfMonth AND @CurrentDate
      AND total_duration < @RequiredDailyMinutes
      AND [status] = 'Attended'
      AND attendance_ID NOT IN (SELECT attendance_ID FROM Deduction WHERE type = 'missing_hours')
    ORDER BY [date] ASC;

    IF @AttendanceID IS NOT NULL
    BEGIN
        SET @DeductionAmount = @RatePerHour * ((@RequiredDailyMinutes - @TotalDurationMinutes) / 60.0);

        INSERT INTO Deduction (emp_ID, [date], amount, type, attendance_ID, [status])
        VALUES (@employee_ID, @CurrentDate, @DeductionAmount, 'missing_hours', @AttendanceID, 'Pending');
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
    DECLARE @RatePerDay decimal(10,2);
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @CurrentDate date = CAST(GETDATE() AS date);
    DECLARE @FirstDayOfMonth date = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);

    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;
    IF @EmployeeSalary IS NOT NULL AND @EmployeeSalary > 0
    BEGIN
        SET @RatePerDay = @EmployeeSalary / 22.0;
    END
    ELSE
    BEGIN
        RETURN;
    END

    INSERT INTO Deduction (emp_ID, [date], amount, type, attendance_ID, [status])
    SELECT 
        @employee_ID, 
        A.[date], 
        @RatePerDay, 
        'missing_days', 
        A.attendance_ID, 
        'Pending'
    FROM Attendance A
    WHERE A.emp_ID = @employee_ID
      AND A.[date] BETWEEN @FirstDayOfMonth AND @CurrentDate
      AND A.[status] = 'Absent'
      AND A.attendance_ID NOT IN (
          SELECT attendance_ID FROM Deduction 
          WHERE emp_ID = @employee_ID AND type = 'missing_days'
      );
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
    DECLARE @RatePerDay decimal(10,2);
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @CurrentDate date = CAST(GETDATE() AS date);
    DECLARE @FirstDayOfMonth date = DATEADD(month, DATEDIFF(month, 0, @CurrentDate), 0);
    DECLARE @LastDayOfMonth date = DATEADD(day, -1, DATEADD(month, 1, @FirstDayOfMonth));

    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;
    IF @EmployeeSalary IS NOT NULL AND @EmployeeSalary > 0
    BEGIN
        SET @RatePerDay = @EmployeeSalary / 22.0;
    END
    ELSE
    BEGIN
        RETURN;
    END

    INSERT INTO Deduction (emp_ID, [date], amount, type, unpaid_ID, [status])
    SELECT 
        @employee_ID, 
        @CurrentDate, 
        (DATEDIFF(day, 
            CASE WHEN L.start_date < @FirstDayOfMonth THEN @FirstDayOfMonth ELSE L.start_date END,
            CASE WHEN L.end_date > @LastDayOfMonth THEN @LastDayOfMonth ELSE L.end_date END
        ) + 1) * @RatePerDay, 
        'unpaid', 
        L.request_ID, 
        'Pending'
    FROM Leave L
    JOIN Unpaid_Leave UL ON L.request_ID = UL.request_ID
    WHERE UL.emp_ID = @employee_ID
      AND L.final_approval_status = 'approved'
      AND L.start_date <= @LastDayOfMonth
      AND L.end_date >= @FirstDayOfMonth
      AND L.request_ID NOT IN (
          SELECT unpaid_ID FROM Deduction WHERE emp_ID = @employee_ID AND type = 'unpaid'
      );
END
GO


-- 2.4.i
IF OBJECT_ID('Add_Payroll', 'P') IS NOT NULL DROP PROCEDURE Add_Payroll;
GO
CREATE PROCEDURE Add_Payroll
(
    @employee_ID int,
    @from_date date,
    @to_date date
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmployeeSalary decimal(10,2);
    DECLARE @BonusAmount decimal(10,2);
    DECLARE @DeductionsAmount decimal(10,2) = 0.00;
    DECLARE @FinalSalary decimal(10,2);
    DECLARE @PaymentDate date = CAST(GETDATE() AS date);

    SELECT @EmployeeSalary = salary FROM Employee WHERE employee_ID = @employee_ID;
    
    SET @BonusAmount = dbo.Bonus_amount(@employee_ID); 

    SELECT @DeductionsAmount = ISNULL(SUM(amount), 0.00)
    FROM Deduction
    WHERE emp_ID = @employee_ID
      AND [date] BETWEEN @from_date AND @to_date
      AND status = 'Pending';

    SET @FinalSalary = @EmployeeSalary + @BonusAmount - @DeductionsAmount;

    INSERT INTO Payroll (emp_ID, payment_date, final_salary_amount, from_date, to_date, comments, bonus_amount, deductions_amount)
    VALUES (
        @employee_ID, 
        @PaymentDate, 
        @FinalSalary, 
        @from_date, 
        @to_date, 
        'Monthly Payroll Generation', 
        @BonusAmount, 
        @DeductionsAmount
    );

    UPDATE Deduction
    SET status = 'finalized'
    WHERE emp_ID = @employee_ID
      AND [date] BETWEEN @from_date AND @to_date
      AND status = 'Pending';
END
GO