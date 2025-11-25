GO
IF OBJECT_ID('HRLoginValidation') IS NOT NULL
    DROP FUNCTION HRLoginValidation;
GO

CREATE FUNCTION HRLoginValidation
(
    @employee_ID INT,
    @password VARCHAR(50)
)
RETURNS BIT
AS
BEGIN
    DECLARE @isValid BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM Employee AS E
        JOIN Employee_Role AS ER ON E.employee_ID = ER.emp_ID
        JOIN [Role] AS R ON ER.role_name = R.role_name
        WHERE E.employee_ID = @employee_ID
          AND E.password = @password
          AND R.role_name = 'HR Representative' 
    )
    BEGIN
        SET @isValid = 1;
    END

    RETURN @isValid;
END;
GO
--////////////--

GO
IF OBJECT_ID('HR_approval_an_acc') IS NOT NULL
    DROP PROCEDURE HR_approval_an_acc;
GO

CREATE PROCEDURE HR_approval_an_acc
(
    @request_ID INT,
    @HR_ID INT,
    @approval_status VARCHAR(50) 
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @approval_status NOT IN ('approved', 'rejected')
    BEGIN
        RAISERROR('Invalid approval status. Use ''approved'' or ''rejected''.', 16, 1);
        RETURN;
    END

    UPDATE Employee_Approve_Leave
    SET status = @approval_status
    WHERE [Leave ID] = @request_ID
      AND Emp1_ID = @HR_ID;

    IF @approval_status = 'rejected'
    BEGIN
        UPDATE Leave
        SET final_approval_status = 'rejected'
        WHERE request_ID = @request_ID;
        RETURN;
    END

    IF @approval_status = 'approved'
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM Employee_Approve_Leave
            WHERE [Leave ID] = @request_ID
              AND status IN ('rejected', 'pending')
        )
        BEGIN
            RETURN;
        END

        DECLARE @LeaveType VARCHAR(50);
        DECLARE @EmpID INT;
        DECLARE @NumDays INT;
        DECLARE @Balance INT;

        SELECT @EmpID = L.emp_ID, @NumDays = L.num_days
        FROM Leave AS L
        WHERE L.request_ID = @request_ID;

        IF EXISTS (SELECT 1 FROM Annual_Leave WHERE request_ID = @request_ID)
        BEGIN
            SET @LeaveType = 'Annual';
            SELECT @Balance = annual_balance FROM Employee WHERE employee_ID = @EmpID;
        END
        ELSE IF EXISTS (SELECT 1 FROM Accidental_Leave WHERE request_ID = @request_ID)
        BEGIN
            SET @LeaveType = 'Accidental';
            SELECT @Balance = accidental_balance FROM Employee WHERE employee_ID = @EmpID;
        END
        ELSE
        BEGIN
            RAISERROR('Request ID is not a valid Annual or Accidental Leave request.', 16, 1);
            RETURN;
        END

        IF @Balance >= @NumDays
        BEGIN
            UPDATE Leave
            SET final_approval_status = 'approved'
            WHERE request_ID = @request_ID;

            IF @LeaveType = 'Annual'
            BEGIN
                UPDATE Employee
                SET annual_balance = annual_balance - @NumDays
                WHERE employee_ID = @EmpID;
            END
            ELSE 
            BEGIN
                UPDATE Employee
                SET accidental_balance = accidental_balance - @NumDays
                WHERE employee_ID = @EmpID;
            END
        END
        ELSE
        BEGIN
            UPDATE Leave
            SET final_approval_status = 'rejected'
            WHERE request_ID = @request_ID;

            RAISERROR('Leave request rejected: Insufficient balance for %s leave.', 16, 1, @LeaveType);
        END
    END
END;
GO



--/////////////////////--

GO
IF OBJECT_ID('HR_approval_unpaid') IS NOT NULL
    DROP PROCEDURE HR_approval_unpaid;
GO

CREATE PROCEDURE HR_approval_unpaid
(
    @request_ID INT,
    @HR_ID INT,
    @approval_status VARCHAR(50) 
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NumDays INT;
    DECLARE @DocExists BIT;

    IF @approval_status NOT IN ('approved', 'rejected')
    BEGIN
        RAISERROR('Invalid approval status. Use ''approved'' or ''rejected''.', 16, 1);
        RETURN;
    END

    UPDATE Employee_Approve_Leave
    SET status = @approval_status
    WHERE [Leave ID] = @request_ID
      AND Emp1_ID = @HR_ID;

    IF @approval_status = 'rejected'
    BEGIN
        UPDATE Leave
        SET final_approval_status = 'rejected'
        WHERE request_ID = @request_ID;
        RETURN;
    END

    IF @approval_status = 'approved'
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM Employee_Approve_Leave
            WHERE [Leave ID] = @request_ID
              AND status IN ('rejected', 'pending')
        )
        BEGIN
            RETURN;
        END

        SELECT @NumDays = L.num_days
        FROM Leave AS L
        WHERE L.request_ID = @request_ID;

        IF @NumDays > 30
        BEGIN
            UPDATE Leave
            SET final_approval_status = 'rejected'
            WHERE request_ID = @request_ID;
            RAISERROR('Unpaid leave rejected: Duration exceeds maximum 30 days.', 16, 1);
            RETURN;
        END

        SET @DocExists = 0;
        IF EXISTS (
            SELECT 1
            FROM Document
            WHERE unpaid_ID = @request_ID 
        )
        BEGIN
            SET @DocExists = 1;
        END

        IF @DocExists = 0
        BEGIN
            UPDATE Leave
            SET final_approval_status = 'rejected'
            WHERE request_ID = @request_ID;
            RAISERROR('Unpaid leave rejected: Required memo document is missing.', 16, 1);
            RETURN;
        END

        UPDATE Leave
        SET final_approval_status = 'approved'
        WHERE request_ID = @request_ID;
    END
END;
GO

--//////////////////////////////////--

GO
IF OBJECT_ID('HR_approval_comp') IS NOT NULL
    DROP PROCEDURE HR_approval_comp;
GO

CREATE PROCEDURE HR_approval_comp
(
    @request_ID INT,
    @HR_ID INT,
    @approval_status VARCHAR(50) 
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EmpID INT;
    DECLARE @OriginalDate DATE;
    DECLARE @LeaveStartDate DATE;

    IF @approval_status NOT IN ('approved', 'rejected')
    BEGIN
        RAISERROR('Invalid approval status. Use ''approved'' or ''rejected''.', 16, 1);
        RETURN;
    END

    UPDATE Employee_Approve_Leave
    SET status = @approval_status
    WHERE [Leave ID] = @request_ID
      AND Emp1_ID = @HR_ID;

    IF @approval_status = 'rejected'
    BEGIN
        UPDATE Leave
        SET final_approval_status = 'rejected'
        WHERE request_ID = @request_ID;
        RETURN;
    END

    IF @approval_status = 'approved'
    BEGIN
        SELECT @EmpID = L.emp_ID,
               @LeaveStartDate = L.start_date
        FROM Leave AS L
        WHERE L.request_ID = @request_ID;

        SELECT @OriginalDate = date_of_original_workday
        FROM Compensation_Leave
        WHERE request_ID = @request_ID;

        DECLARE @WorkDurationMinutes INT;

        SELECT @WorkDurationMinutes = DATEDIFF(MINUTE, A.check_in_time, A.check_out_time)
        FROM Attendance AS A
        WHERE A.emp_ID = @EmpID
          AND A.date = @OriginalDate
          AND A.status = 'Attended';

        IF @WorkDurationMinutes IS NULL OR @WorkDurationMinutes < 480 -- 480 minutes = 8 hours
        BEGIN
            UPDATE Leave
            SET final_approval_status = 'rejected'
            WHERE request_ID = @request_ID;
            RAISERROR('Compensation leave rejected: Employee did not work 8 hours or more on the original workday.', 16, 1);
            RETURN;
        END

        IF MONTH(@LeaveStartDate) <> MONTH(@OriginalDate) OR YEAR(@LeaveStartDate) <> YEAR(@OriginalDate)
        BEGIN
            UPDATE Leave
            SET final_approval_status = 'rejected'
            WHERE request_ID = @request_ID;
            RAISERROR('Compensation leave rejected: Leave must be taken within the same month as the original workday.', 16, 1);
            RETURN;
        END

        UPDATE Leave
        SET final_approval_status = 'approved'
        WHERE request_ID = @request_ID;
    END
END;
GO

--//////////////////////////--

GO
IF OBJECT_ID('Deduction_hours') IS NOT NULL
    DROP PROCEDURE Deduction_hours;
GO

CREATE PROCEDURE Deduction_hours
(
    @attendance_ID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EmpID INT;
    DECLARE @AttendanceDate DATE;
    DECLARE @TotalDuration TIME;
    DECLARE @Salary DECIMAL(10, 2);
    DECLARE @HourlyRate DECIMAL(10, 2);
    DECLARE @MissingMinutes INT;
    DECLARE @MissingHours DECIMAL(10, 2);
    DECLARE @DeductionAmount DECIMAL(10, 2);

    SELECT @EmpID = A.emp_ID,
           @AttendanceDate = A.date,
           @TotalDuration = A.total_duration,
           @Salary = E.salary
    FROM Attendance AS A
    JOIN Employee AS E ON A.emp_ID = E.employee_ID
    WHERE A.attendance_ID = @attendance_ID
      AND A.status = 'Attended';

    IF @EmpID IS NULL
    BEGIN
        RETURN;
    END

    SET @MissingMinutes = 480 - (DATEPART(HOUR, @TotalDuration) * 60 + DATEPART(MINUTE, @TotalDuration));

    IF @MissingMinutes <= 0
    BEGIN
        RETURN;
    END

    SET @MissingHours = CAST(@MissingMinutes AS DECIMAL(10, 2)) / 60.0;

    SET @HourlyRate = (@Salary / 22.0) / 8.0;

    SET @DeductionAmount = @HourlyRate * @MissingHours;

    INSERT INTO Deduction (emp_ID, [date], amount, type, status, attendance_ID)
    VALUES (@EmpID, @AttendanceDate, @DeductionAmount, 'missing_hours', 'pending', @attendance_ID);
END;
GO


--///////////////////////////--

GO
IF OBJECT_ID('Deduction_days') IS NOT NULL
    DROP PROCEDURE Deduction_days;
GO

CREATE PROCEDURE Deduction_days
(
    @attendance_ID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EmpID INT;
    DECLARE @AttendanceDate DATE;
    DECLARE @Salary DECIMAL(10, 2);
    DECLARE @DailyRate DECIMAL(10, 2);
    DECLARE @DeductionAmount DECIMAL(10, 2);


    SELECT @EmpID = A.emp_ID,
           @AttendanceDate = A.date,
           @Salary = E.salary
    FROM Attendance AS A
    JOIN Employee AS E ON A.emp_ID = E.employee_ID
    WHERE A.attendance_ID = @attendance_ID
      AND A.status = 'Absent';

   
    IF @EmpID IS NULL
    BEGIN
        RETURN;
    END

 
    SET @DailyRate = @Salary / 22.0;

  
    SET @DeductionAmount = @DailyRate;

 
    INSERT INTO Deduction (emp_ID, [date], amount, type, status, attendance_ID)
    VALUES (@EmpID, @AttendanceDate, @DeductionAmount, 'missing_days', 'pending', @attendance_ID);
END;
GO


--////////////////////////////////

GO
IF OBJECT_ID('Deduction_unpaid') IS NOT NULL
    DROP PROCEDURE Deduction_unpaid;
GO

CREATE PROCEDURE Deduction_unpaid
(
    @request_ID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EmpID INT;
    DECLARE @NumDays INT;
    DECLARE @StartDate DATE;
    DECLARE @Salary DECIMAL(10, 2);
    DECLARE @DailyRate DECIMAL(10, 2);
    DECLARE @DeductionAmount DECIMAL(10, 2);

    SELECT @EmpID = L.emp_ID,
           @NumDays = L.num_days,
           @StartDate = L.start_date,
           @Salary = E.salary
    FROM Leave AS L
    JOIN Unpaid_Leave AS UL ON L.request_ID = UL.request_ID
    JOIN Employee AS E ON L.emp_ID = E.employee_ID
    WHERE L.request_ID = @request_ID
      AND L.final_approval_status = 'approved';

    IF @EmpID IS NULL
    BEGIN
        RETURN;
    END

    SET @DailyRate = @Salary / 22.0;

    SET @DeductionAmount = @DailyRate * @NumDays;

    INSERT INTO Deduction (emp_ID, [date], amount, type, status, unpaid_ID)
    VALUES (@EmpID, @StartDate, @DeductionAmount, 'unpaid', 'pending', @request_ID);

END;
GO


--////////////////////////



