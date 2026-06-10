-- PostgreSQL Stored Procedures & Functions for AlphaPos Employee Payroll

-- =========================================================================
-- FUNCTION: Calculate Actual Worked Hours for an Employee in a Range
-- Deducts breaks and converts to decimal hours.
-- =========================================================================

CREATE OR REPLACE FUNCTION calculate_employee_hours(
    p_employee_id UUID,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS DECIMAL(8,2) AS $$
DECLARE
    v_total_hours DECIMAL(8,2);
BEGIN
    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (clock_out - clock_in))/3600.0 - (break_duration::DECIMAL / 60.0)
    ), 0.00)
    INTO v_total_hours
    FROM timecards
    WHERE employee_id = p_employee_id
      AND status = 'approved'
      AND clock_in::DATE >= p_start_date
      AND clock_out::DATE <= p_end_date;
      
    RETURN v_total_hours;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- FUNCTION: Calculate Overtime Hours for an Employee in a Range
-- Convers overtime minutes from approved timecards to hours.
-- =========================================================================

CREATE OR REPLACE FUNCTION calculate_employee_overtime_hours(
    p_employee_id UUID,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS DECIMAL(8,2) AS $$
DECLARE
    v_ot_hours DECIMAL(8,2);
BEGIN
    SELECT COALESCE(SUM(
        overtime_minutes::DECIMAL / 60.0
    ), 0.00)
    INTO v_ot_hours
    FROM timecards
    WHERE employee_id = p_employee_id
      AND status = 'approved'
      AND clock_in::DATE >= p_start_date
      AND clock_out::DATE <= p_end_date;
      
    RETURN v_ot_hours;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- PROCEDURE: Generate Payroll Slips for a Specific Date Range
-- Computes base pay, overtime (1.5x hourly rate), SSF deductions (5%), and net pay.
-- =========================================================================

CREATE OR REPLACE PROCEDURE generate_payroll_for_period(
    p_merchant_id UUID,
    p_start_date DATE,
    p_end_date DATE,
    p_payment_date DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    r_emp RECORD;
    v_worked_hours DECIMAL(6,2);
    v_ot_hours DECIMAL(6,2);
    v_base_pay DECIMAL(10,2);
    v_ot_pay DECIMAL(10,2);
    v_deductions DECIMAL(10,2);
    v_net_pay DECIMAL(10,2);
    v_days_worked INTEGER;
    
    -- Constants for Thai Payroll rules
    c_ssf_rate CONSTANT DECIMAL(5,4) := 0.0500; -- 5% Social Security Fund (ประกันสังคม)
    c_ssf_max CONSTANT DECIMAL(10,2) := 750.00;  -- SSF contribution cap at 750 THB (5% of 15,000 THB)
    c_ot_multiplier CONSTANT DECIMAL(3,2) := 1.50; -- Overtime pay multiplier
BEGIN
    -- 2. Iterate through all active employees for the specified merchant
    FOR r_emp IN 
        SELECT id, first_name, last_name, employment_type, pay_rate 
        FROM employees 
        WHERE merchant_id = p_merchant_id
          AND (resigned_at IS NULL OR resigned_at >= p_start_date)
    LOOP
        -- Calculate hours & overtime base payouts
        IF r_emp.employment_type = 'hourly' THEN
            v_worked_hours := calculate_employee_hours(r_emp.id, p_start_date, p_end_date);
            v_ot_hours := calculate_employee_overtime_hours(r_emp.id, p_start_date, p_end_date);
            
            v_base_pay := ROUND(v_worked_hours * r_emp.pay_rate, 2);
            v_ot_pay := ROUND(v_ot_hours * (r_emp.pay_rate * c_ot_multiplier), 2);
        ELSIF r_emp.employment_type = 'daily' THEN
            SELECT COALESCE(COUNT(DISTINCT clock_in::DATE), 0)
            INTO v_days_worked
            FROM timecards
            WHERE employee_id = r_emp.id
              AND status = 'approved'
              AND clock_in::DATE >= p_start_date
              AND clock_out::DATE <= p_end_date;

            v_worked_hours := calculate_employee_hours(r_emp.id, p_start_date, p_end_date);
            v_ot_hours := calculate_employee_overtime_hours(r_emp.id, p_start_date, p_end_date);

            v_base_pay := ROUND(v_days_worked * r_emp.pay_rate, 2);
            -- Daily OT hourly rate is daily rate / 8
            v_ot_pay := ROUND(v_ot_hours * ((r_emp.pay_rate / 8.0) * c_ot_multiplier), 2);
        ELSE
            -- Monthly Salaried (base salary is fixed)
            v_worked_hours := 0.00;
            v_ot_hours := calculate_employee_overtime_hours(r_emp.id, p_start_date, p_end_date);
            
            v_base_pay := r_emp.pay_rate;
            -- Hourly OT rate for monthly staff calculated as: (Monthly Salary / 30 days / 8 hours) * 1.5
            v_ot_pay := ROUND(v_ot_hours * ((r_emp.pay_rate / 240.0) * c_ot_multiplier), 2);
        END IF;

        -- 3. Calculate Deductions (e.g. Social Security Fund SSF)
        -- In Thailand, SSF is calculated on gross base salary up to a max threshold of 15,000 THB base
        IF (v_base_pay * c_ssf_rate) > c_ssf_max THEN
            v_deductions := c_ssf_max;
        ELSE
            v_deductions := ROUND(v_base_pay * c_ssf_rate, 2);
        END IF;

        -- 4. Calculate Net Pay
        v_net_pay := v_base_pay + v_ot_pay - v_deductions;

        -- 5. Output payroll result (actual payroll_slips table requires migration to create)
        RAISE NOTICE 'Payroll for % %: Base=%, OT=%, Deductions=%, Net=%',
            r_emp.first_name, r_emp.last_name, v_base_pay, v_ot_pay, v_deductions, v_net_pay;
    END LOOP;
END;
$$;

-- =========================================================================
-- PROCEDURE: Approve or Reject a Timecard (Timecard Audit Control)
-- =========================================================================

CREATE OR REPLACE PROCEDURE audit_employee_timecard(
    p_merchant_id UUID,
    p_timecard_id UUID,
    p_verifier_id UUID,
    p_status VARCHAR(20), -- 'approved', 'rejected'
    p_notes TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE timecards
    SET status = p_status,
        notes = COALESCE(notes || ' | ', '') || p_notes,
        updated_at = CURRENT_TIMESTAMP,
        is_synced = FALSE
    WHERE id = p_timecard_id
      AND merchant_id = p_merchant_id;
END;
$$;
