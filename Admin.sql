USE University_HR_ManagementSystem_Team_101;
GO
CREATE PROCEDURE Update_Status_Doc
AS
UPDATE Document
SET status = 'expired'
WHERE expiry_date < CAST(GETDATE() AS date)
  AND status <> 'expired';
GO

CREATE PROCEDURE Remove_Deductions
AS
DELETE FROM Deduction
WHERE emp_ID IN (
    SELECT employee_ID 
    FROM Employee 
    WHERE employment_status = 'resigned'
);
GO


CREATE PROCEDURE Update_Employment_Status
    @Employee_ID int
AS
BEGIN
    DECLARE @today date = CAST(GETDATE() AS date);

    -- If employee is resigned or in notice_period → do nothing
    IF (SELECT employment_status 
        FROM Employee 
        WHERE employee_ID = @Employee_ID)
        IN ('resigned', 'notice_period')
        RETURN;
    
    -- Annual Leave
    IF EXISTS (
        SELECT 1
        FROM Annual_Leave AL
        JOIN [Leave] L ON L.request_ID = AL.request_ID
        WHERE AL.emp_ID = @Employee_ID
          AND L.final_approval_status IN ('approved','pending')
          AND L.startdate <= @today
          AND L.end_date >= @today
    )
        UPDATE Employee SET employment_status = 'onleave' WHERE employee_ID = @Employee_ID;
    ELSE
    
    -- Accidental Leave
    IF EXISTS (
        SELECT 1
        FROM Accidental_Leave AC
        JOIN [Leave] L ON L.request_ID = AC.request_ID
        WHERE AC.emp_ID = @Employee_ID
          AND L.final_approval_status IN ('approved','pending')
          AND L.startdate <= @today
          AND L.end_date >= @today
    )
        UPDATE Employee SET employment_status = 'onleave' WHERE employee_ID = @Employee_ID;
    ELSE
    
    -- Medical Leave
    IF EXISTS (
        SELECT 1
        FROM Medical_Leave M
        JOIN [Leave] L ON L.request_ID = M.request_ID
        WHERE M.emp_ID = @Employee_ID
          AND L.final_approval_status IN ('approved','pending')
          AND L.startdate <= @today
          AND L.end_date >= @today
    )
        UPDATE Employee SET employment_status = 'onleave' WHERE employee_ID = @Employee_ID;
    ELSE

    -- Unpaid Leave
    IF EXISTS (
        SELECT 1
        FROM Unpaid_Leave U
        JOIN [Leave] L ON L.request_ID = U.request_ID
        WHERE U.emp_ID = @Employee_ID
          AND L.final_approval_status IN ('approved','pending')
          AND L.startdate <= @today
          AND L.end_date >= @today
    )
        UPDATE Employee SET employment_status = 'onleave' WHERE employee_ID = @Employee_ID;
    ELSE
    
    -- Compensation Leave
    IF EXISTS (
        SELECT 1
        FROM Compensation_Leave C
        JOIN [Leave] L ON L.request_ID = C.request_ID
        WHERE C.emp_ID = @Employee_ID
          AND L.final_approval_status IN ('approved','pending')
          AND L.startdate <= @today
          AND L.end_date >= @today
    )
        UPDATE Employee SET employment_status = 'onleave' WHERE employee_ID = @Employee_ID;
    ELSE

    -- No leave today so employee is active
        UPDATE Employee SET employment_status = 'active' WHERE employee_ID = @Employee_ID;

END;
GO


CREATE PROCEDURE Create_Holiday
AS
CREATE TABLE Holiday (
    holiday_id int IDENTITY(1,1) PRIMARY KEY,
    name varchar(50),
    from_date date,
    to_date date
);
GO

CREATE PROCEDURE Add_Holiday
    @holiday_name varchar(50),
    @from_date date,
    @to_date date
AS
INSERT INTO Holiday(name, from_date, to_date)
VALUES (@holiday_name, @from_date, @to_date);
GO

CREATE PROCEDURE Intitiate_Attendance
AS
DECLARE @today date = CAST(GETDATE() AS date);

INSERT INTO Attendance(date, emp_ID)
SELECT @today, employee_ID
FROM Employee
WHERE employee_ID NOT IN (
    SELECT emp_ID FROM Attendance WHERE date = @today
);
GO

CREATE PROCEDURE Update_Attendance
    @Employee_ID int,
    @check_in time,
    @check_out time
AS
UPDATE Attendance
SET check_in_time = @check_in,
    check_out_time = @check_out,
    status = 'attended'
WHERE emp_ID = @Employee_ID
  AND date = CAST(GETDATE() AS date);
GO

CREATE PROCEDURE Remove_Holiday
AS
DELETE A
FROM Attendance A
JOIN Holiday H
ON A.date BETWEEN H.from_date AND H.to_date;
GO

CREATE PROCEDURE Remove_DayOff
    @Employee_ID int
AS
DELETE FROM Attendance
WHERE emp_ID = @Employee_ID
  AND status = 'absent'
  AND DATENAME(weekday, date) = (
        SELECT official_day_off FROM Employee WHERE employee_ID = @Employee_ID
      );
GO

CREATE PROCEDURE Remove_Approved_Leaves
    @Employee_ID int
AS
BEGIN

    -- Annual Leave
    DELETE A
    FROM Attendance A
    JOIN Annual_Leave AL ON AL.emp_ID = @Employee_ID
    JOIN [Leave] L ON L.request_ID = AL.request_ID
    WHERE A.emp_ID = @Employee_ID
      AND L.final_approval_status = 'approved'
      AND A.date BETWEEN L.startdate AND L.end_date;

    -- Accidental Leave
    DELETE A
    FROM Attendance A
    JOIN Accidental_Leave AC ON AC.emp_ID = @Employee_ID
    JOIN [Leave] L ON L.request_ID = AC.request_ID
    WHERE A.emp_ID = @Employee_ID
      AND L.final_approval_status = 'approved'
      AND A.date BETWEEN L.startdate AND L.end_date;

    -- Medical Leave
    DELETE A
    FROM Attendance A
    JOIN Medical_Leave M ON M.emp_ID = @Employee_ID
    JOIN [Leave] L ON L.request_ID = M.request_ID
    WHERE A.emp_ID = @Employee_ID
      AND L.final_approval_status = 'approved'
      AND A.date BETWEEN L.startdate AND L.end_date;

    -- Unpaid Leave
    DELETE A
    FROM Attendance A
    JOIN Unpaid_Leave U ON U.emp_ID = @Employee_ID
    JOIN [Leave] L ON L.request_ID = U.request_ID
    WHERE A.emp_ID = @Employee_ID
      AND L.final_approval_status = 'approved'
      AND A.date BETWEEN L.startdate AND L.end_date;

    -- Compensation Leave
    DELETE A
    FROM Attendance A
    JOIN Compensation_Leave C ON C.emp_ID = @Employee_ID
    JOIN [Leave] L ON L.request_ID = C.request_ID
    WHERE A.emp_ID = @Employee_ID
      AND L.final_approval_status = 'approved'
      AND A.date BETWEEN L.startdate AND L.end_date;

END;
GO

CREATE PROCEDURE Replace_employee
    @Emp1_ID int,
    @Emp2_ID int,
    @from_date date,
    @to_date date
AS
INSERT INTO Employee_Replace_Employee(Emp1_ID, Emp2_ID, from_date, to_date)
VALUES (@Emp1_ID, @Emp2_ID, @from_date, @to_date);
GO
