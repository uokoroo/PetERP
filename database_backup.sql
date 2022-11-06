--
-- PostgreSQL database dump
--

-- Dumped from database version 14.5
-- Dumped by pg_dump version 14.5 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: basic_auth; Type: SCHEMA; Schema: -; Owner: doadmin
--

CREATE SCHEMA basic_auth;


ALTER SCHEMA basic_auth OWNER TO doadmin;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA basic_auth;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: jwt_token; Type: TYPE; Schema: basic_auth; Owner: doadmin
--

CREATE TYPE basic_auth.jwt_token AS (
	token text
);


ALTER TYPE basic_auth.jwt_token OWNER TO doadmin;

--
-- Name: algorithm_sign(text, text, text); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.algorithm_sign(signables text, secret text, algorithm text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
WITH
  alg AS (
    SELECT CASE
      WHEN algorithm = 'HS256' THEN 'sha256'
      WHEN algorithm = 'HS384' THEN 'sha384'
      WHEN algorithm = 'HS512' THEN 'sha512'
      ELSE '' END AS id)  -- hmac throws error
SELECT basic_auth.url_encode(basic_auth.hmac(signables, secret, alg.id)) FROM alg;
$$;


ALTER FUNCTION basic_auth.algorithm_sign(signables text, secret text, algorithm text) OWNER TO doadmin;

--
-- Name: check_role_exists(); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.check_role_exists() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if not exists (select 1 from pg_roles as r where r.rolname = new.role) then
    raise foreign_key_violation using message =
      'unknown database role: ' || new.role;
    return null;
  end if;
  return new;
end
$$;


ALTER FUNCTION basic_auth.check_role_exists() OWNER TO doadmin;

--
-- Name: encrypt_pass(); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.encrypt_pass() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if tg_op = 'INSERT' or new.pass <> old.pass then
    new.pass = basic_auth.crypt(new.pass, basic_auth.gen_salt('bf'));
  end if;
  return new;
end
$$;


ALTER FUNCTION basic_auth.encrypt_pass() OWNER TO doadmin;

--
-- Name: login(text, text); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.login(id text, pass text) RETURNS basic_auth.jwt_token
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  _role name;
  result basic_auth.jwt_token;
begin
  -- check id and password
  select basic_auth.user_role(id, pass) into _role;
  if _role is null then
    raise invalid_password using message = 'invalid user or password';
  end if;

  select sign(
      row_to_json(r), '6cCALT5pL29Qs6tdhCpoVcrG3ZpsNnTm'
    ) as token
    from (
      select _role as role, login.id as id,
         extract(epoch from now())::integer + 60*60*24 as exp
    ) r
    into result;
  return result;
end;
$$;


ALTER FUNCTION basic_auth.login(id text, pass text) OWNER TO doadmin;

--
-- Name: sign(json, text, text); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.sign(payload json, secret text, algorithm text DEFAULT 'HS256'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
WITH
  header AS (
    SELECT basic_auth.url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8')) AS data
    ),
  payload AS (
    SELECT basic_auth.url_encode(convert_to(payload::text, 'utf8')) AS data
    ),
  signables AS (
    SELECT header.data || '.' || payload.data AS data FROM header, payload
    )
SELECT
    signables.data || '.' ||
    basic_auth.algorithm_sign(signables.data, secret, algorithm) FROM signables;
$$;


ALTER FUNCTION basic_auth.sign(payload json, secret text, algorithm text) OWNER TO doadmin;

--
-- Name: url_decode(text); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.url_decode(data text) RETURNS bytea
    LANGUAGE sql IMMUTABLE
    AS $$
WITH t AS (SELECT translate(data, '-_', '+/') AS trans),
     rem AS (SELECT length(t.trans) % 4 AS remainder FROM t) -- compute padding size
    SELECT decode(
        t.trans ||
        CASE WHEN rem.remainder > 0
           THEN repeat('=', (4 - rem.remainder))
           ELSE '' END,
    'base64') FROM t, rem;
$$;


ALTER FUNCTION basic_auth.url_decode(data text) OWNER TO doadmin;

--
-- Name: url_encode(bytea); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.url_encode(data bytea) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;


ALTER FUNCTION basic_auth.url_encode(data bytea) OWNER TO doadmin;

--
-- Name: user_role(text, text); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.user_role(id text, pass text) RETURNS name
    LANGUAGE plpgsql
    AS $$
begin
  return (
  select role from basic_auth.users
   where users.id = user_role.id
     and users.pass = basic_auth.crypt(user_role.pass, users.pass)
  );
end;
$$;


ALTER FUNCTION basic_auth.user_role(id text, pass text) OWNER TO doadmin;

--
-- Name: verify(text, text, text); Type: FUNCTION; Schema: basic_auth; Owner: doadmin
--

CREATE FUNCTION basic_auth.verify(token text, secret text, algorithm text DEFAULT 'HS256'::text) RETURNS TABLE(header json, payload json, valid boolean)
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT
    convert_from(basic_auth.url_decode(r[1]), 'utf8')::json AS header,
    convert_from(basic_auth.url_decode(r[2]), 'utf8')::json AS payload,
    r[3] = basic_auth.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) AS valid
  FROM regexp_split_to_array(token, '\.') r;
$$;


ALTER FUNCTION basic_auth.verify(token text, secret text, algorithm text) OWNER TO doadmin;

--
-- Name: adduploader(integer, text, text); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.adduploader(integer, text, text) RETURNS text
    LANGUAGE plpgsql
    AS $_$

DECLARE

  
  email ALIAS FOR $3; 

BEGIN 

  IF email NOT LIKE '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$' THEN

    RAISE EXCEPTION 'Wrong E-mail format %', email
        USING HINT = 'Please check your E-mail format.';

  END IF ; 

  INSERT INTO uploader VALUES(u_id,username,email);

  IF NOT FOUND THEN
    RETURN 'Error';
  END IF;
  RETURN 'Successfully added' ; 

EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'This ID already exists. Specify another one.' ; 
  RETURN 'Error' ; 

END ; $_$;


ALTER FUNCTION public.adduploader(integer, text, text) OWNER TO doadmin;

--
-- Name: apply_course_charges(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.apply_course_charges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        t_amount float;
        session int;
    BEGIN

        if tg_op = 'INSERT' then
            select session_id from sections where section_id=new.section_id into session;
            select ((select credit_price from settings) * (
            select distinct credit_hours from courses c
                inner join sections s on s.course_id = c.course_id
                inner join student_enrollment se on se.section_id = s.section_id where se.section_id = new.section_id)) into t_amount;
            insert into transaction(student_id, transaction_type, description, amount, session_id) VALUES (new.student_id,'debit','System: Course Debit',t_amount,session);
            return new;
        elseif tg_op = 'DELETE' then
            select session_id from sections where section_id=old.section_id into session;
            t_amount := COALESCE((select credit_price from settings) * (
            select distinct credit_hours from courses c
                inner join sections s on s.course_id = c.course_id
                inner join student_enrollment se on se.section_id = s.section_id where se.section_id = old.section_id),285000);
            insert into transaction(student_id, transaction_type, description, amount,session_id) VALUES (old.student_id,'credit','System: Course Credit',t_amount,session);
            return old;
        end if;
end;
$$;


ALTER FUNCTION public.apply_course_charges() OWNER TO doadmin;

--
-- Name: are_prerequisites_satisfied(character varying, integer); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.are_prerequisites_satisfied(student_id character varying, course_id integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$BEGIN
    return true;
end;

$$;


ALTER FUNCTION public.are_prerequisites_satisfied(student_id character varying, course_id integer) OWNER TO doadmin;

--
-- Name: conflicts_with_registration(integer, character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.conflicts_with_registration(section_id integer, student_id character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
    section_time_id int;
    t2              int;

BEGIN
    t2 := (select s.section_time_id from sections s where s.section_id = conflicts_with_registration.section_id);
    for section_time_id in (select s.section_time_id
                            from sections s
                                     inner join
                                 student_enrollment se on s.section_id = se.section_id
                                     inner join session s2 on s.session_id = s2.session_id
--             for this to work, the session states have to be more than 3. So registration is for a session that is not past early and late registration
                            where se.student_id = conflicts_with_registration.student_id
                              and s2.status = 'active'
                              and s2.state_id < 3)
        loop

            if is_time_conflicting(section_time_id, t2) then
                return true;
            end if;

        end loop;
    return false;
end;
$$;


ALTER FUNCTION public.conflicts_with_registration(section_id integer, student_id character varying) OWNER TO doadmin;

--
-- Name: create_user_student(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.create_user_student() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        role varchar(50);
    BEGIN
        if tg_table_name = 'students' then
            role = 'student';
        elseif tg_table_name = 'faculty' then
            role = 'faculty';
        else
            role = 'anon';
        end if;
        if not (select new.student_id in (select id from basic_auth.users)) THEN
            INSERT INTO basic_auth.users(id, pass, role) VALUES (new.student_id,new.password,role);
            new.password = 'valid';

        else
            raise exception 'Duplicate user' using hint = 'User already exists';
        END IF;
RETURN new;
end;
$$;


ALTER FUNCTION public.create_user_student() OWNER TO doadmin;

--
-- Name: get_account_balance(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_account_balance() RETURNS integer
    LANGUAGE plpgsql
    AS $$
    declare
    amount float;
    type varchar;
    total float = 0;
    BEGIN
    for amount,type in (select transaction.amount,transaction_type from transaction where student_id=current_setting('request.jwt.claims', true)::json->>'id') loop
        if type = 'credit' then
            total = total + amount;
        else
            total = total - amount;
        end if;
        end loop;
    return total;
end;

$$;


ALTER FUNCTION public.get_account_balance() OWNER TO doadmin;

--
-- Name: get_age(date); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_age(birthday date) RETURNS interval
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN age(birthday);
END
$$;


ALTER FUNCTION public.get_age(birthday date) OWNER TO doadmin;

--
-- Name: get_attempted_hours(character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_attempted_hours(input_student_id character varying) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    return COALESCE((select sum(credit_hours)
                     from courses
                              inner join sections s on courses.course_id = s.course_id
                              inner join student_enrollment se on s.section_id = se.section_id
                     where se.student_id = input_student_id
                       and grade is not null), 0);
end;
$$;


ALTER FUNCTION public.get_attempted_hours(input_student_id character varying) OWNER TO doadmin;

--
-- Name: get_cgpa(text); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_cgpa(student_id text) RETURNS double precision
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

BEGIN
    return get_total_quality_points(student_id)/get_attempted_hours(student_id);
end;
$$;


ALTER FUNCTION public.get_cgpa(student_id text) OWNER TO doadmin;

--
-- Name: get_earned_hours(character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_earned_hours(input_student_id character varying) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    return COALESCE((select sum(credit_hours)
                     from courses
                              inner join sections s on courses.course_id = s.course_id
                              inner join student_enrollment se on s.section_id = se.section_id
                     where se.student_id = input_student_id
                       and grade is not null
                       and is_passing_grade(grade, courses.course_id)), 0);
end;
$$;


ALTER FUNCTION public.get_earned_hours(input_student_id character varying) OWNER TO doadmin;

--
-- Name: get_enrollment_number(integer); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_enrollment_number(section_id integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    return ((select count(*)
             from student_enrollment
                      inner join sections s2 on s2.section_id = student_enrollment.section_id
             where student_enrollment.section_id = get_enrollment_number.section_id));
end;
$$;


ALTER FUNCTION public.get_enrollment_number(section_id integer) OWNER TO doadmin;

--
-- Name: get_id(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_id() RETURNS character varying
    LANGUAGE plpgsql
    AS $$BEGIN
    RETURN current_setting('request.jwt.claims', true)::json->>'id';
end;
$$;


ALTER FUNCTION public.get_id() OWNER TO doadmin;

--
-- Name: get_max_courses(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_max_courses() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$BEGIN
        return ((select mc.max from max_courses mc
            inner join students s on s.school=mc.school
                               where s.student_id= current_setting('request.jwt.claims', true)::json->>'id')
                                                                                                           +
                COALESCE(
                    (select o.additional_courses from overloads o
                        inner join session s2 on o.session_id = s2.session_id
                        WHERE s2.status = 'active'
                        and s2.state_id < 3
                        and o.student_id = current_setting('request.jwt.claims', true)::json->>'id'
                                                          and o.state='Accepted'),0));
end;
$$;


ALTER FUNCTION public.get_max_courses() OWNER TO doadmin;

--
-- Name: get_role(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_role() RETURNS character varying
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$BEGIN
    RETURN (select role from basic_auth.users where id=current_setting('request.jwt.claims', true)::json->>'id');
end;
$$;


ALTER FUNCTION public.get_role() OWNER TO doadmin;

--
-- Name: get_student_year(character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_student_year(input_student_id character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    BEGIN
    return (select year_id from student_year_per_program
                        where
                            program_id = (
                            select program_id from students where
                                                                student_id=input_student_id AND
                                                                 get_earned_hours(input_student_id) >= from_credits and
                                                                 get_earned_hours(input_student_id) < to_credits));


end;
$$;


ALTER FUNCTION public.get_student_year(input_student_id character varying) OWNER TO doadmin;

--
-- Name: get_total_quality_points(text); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_total_quality_points(student_id text) RETURNS double precision
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
    declare
        total float = 0;
        qp float;
        c integer;
        g varchar;
BEGIN
    for c,g in (
select c.course_id,se.grade from student_enrollment se
        inner join sections s on s.section_id = se.section_id
        inner join courses c on c.course_id = s.course_id
        inner join session s2 on s.session_id = s2.session_id
        where s2.status <> 'active' and se.student_id = get_total_quality_points.student_id) loop
        qp = quality_points(c,g);
        total = total + qp;
        end loop;
    return total;
end;
$$;


ALTER FUNCTION public.get_total_quality_points(student_id text) OWNER TO doadmin;

--
-- Name: grade_exists(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.grade_exists() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    if new.grade not in (select grade from grade_assignments) then
        raise exception 'Grade % not recognized', new.grade using hint = 'Enter a valid grade';
    end if;
    return new;
end;
$$;


ALTER FUNCTION public.grade_exists() OWNER TO doadmin;

--
-- Name: is_class_full(integer); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.is_class_full(section_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$BEGIN
    return ((select count(*) from student_enrollment
                inner join sections s2 on s2.section_id = student_enrollment.section_id
                             where
                                 student_enrollment.section_id = is_class_full.section_id) >= (select capacity from sections s
                                                                                                               where s.section_id = is_class_full.section_id));
end;
$$;


ALTER FUNCTION public.is_class_full(section_id integer) OWNER TO doadmin;

--
-- Name: is_course_limit_reached(character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.is_course_limit_reached(student_id character varying) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    return
         (((select count(*)
             from sections s
                      inner join session s2 on s.session_id = s2.session_id
                      inner join student_enrollment se on s.section_id = se.section_id
             WHERE s2.status = 'active'
               and s2.state_id < 3
               and se.student_id = is_course_limit_reached.student_id) +
            COALESCE((select distinct additional_courses
                      from overloads o
                               inner join session s2 on o.session_id = s2.session_id
                      WHERE s2.status = 'active'
                        and s2.state_id < 3
                        and o.student_id = is_course_limit_reached.student_id), 0)) = (select max
                                                                                       from max_courses mc
                                                                                                inner join schools s3 on s3.school_id = mc.school
                                                                                                inner join students s4 on mc.school = s4.school where s4.student_id = is_course_limit_reached.student_id));

end;
$$;


ALTER FUNCTION public.is_course_limit_reached(student_id character varying) OWNER TO doadmin;

--
-- Name: is_passing_grade(character varying, integer); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.is_passing_grade(grade character varying, course integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$BEGIN
    return (select id from grade_assignments where grade_assignments.grade = is_passing_grade.grade limit 1) <= 7;
end;
$$;


ALTER FUNCTION public.is_passing_grade(grade character varying, course integer) OWNER TO doadmin;

--
-- Name: is_passing_grade(character varying, character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.is_passing_grade(grade character varying, course character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$BEGIN
    return (select id from grade_assignments where grade_assignments.grade = is_passing_grade.grade) <= 7;
end;

$$;


ALTER FUNCTION public.is_passing_grade(grade character varying, course character varying) OWNER TO doadmin;

--
-- Name: is_time_conflicting(integer, integer); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.is_time_conflicting(t1 integer, t2 integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    day            int;
    time           int;
    time_hour_t1   int;
    time_min_t1    int;
    time_start_hr  int;
    time_start_min int;
    time_end_hr    int;
    time_end_min   int;
BEGIN
    if t1 = t2 then
        return true;
    end if;

    for day in (select d.day_id
                from class_dates_abbrev
                         inner join class_dates cd on class_dates_abbrev.class_abbrev_id = cd.class_abbrev_id
                         inner join days d on d.day_id = cd.day_id
                     -- this could be the problem. Maybe the select is returning an array and the equality isn't holding
                where cd.class_abbrev_id = (select class_dates_abbrev from section_times where section_time_id = t1))
        loop
            if day = ANY ( (select d.day_id
                            from class_dates_abbrev
                                     inner join class_dates cd
                                                on class_dates_abbrev.class_abbrev_id = cd.class_abbrev_id
                                     inner join days d on d.day_id = cd.day_id
                            where cd.class_abbrev_id =
                                  (select class_dates_abbrev from section_times where section_time_id = t2))) then
                select distinct start_hour
                into time_hour_t1
                from section_times
                         inner join class_times ct on ct.class_time_id = section_times.class_time_id
                where section_times.class_time_id =
                      (select class_time_id from section_times where section_time_id = t1);
                select distinct start_minute
                into time_min_t1
                from section_times
                         inner join class_times ct on ct.class_time_id = section_times.class_time_id
                where section_times.class_time_id =
                      (select class_time_id from section_times where section_time_id = t1);
                select distinct start_hour
                into time_start_hr
                from section_times
                         inner join class_times ct on ct.class_time_id = section_times.class_time_id
                where section_times.class_time_id =
                      (select class_time_id from section_times where section_time_id = t2);

                select distinct start_minute
                into time_start_min
                from section_times
                         inner join class_times ct on ct.class_time_id = section_times.class_time_id
                where section_times.class_time_id =
                      (select class_time_id from section_times where section_time_id = t2);

                select distinct end_hour
                into time_end_hr
                from section_times
                         inner join class_times ct on ct.class_time_id = section_times.class_time_id
                where section_times.class_time_id =
                      (select class_time_id from section_times where section_time_id = t2);
                select distinct end_minute
                into time_end_min
                from section_times
                         inner join class_times ct on ct.class_time_id = section_times.class_time_id
                where section_times.class_time_id =
                      (select class_time_id from section_times where section_time_id = t2);

                select time_hour_t1 * 60 + time_min_t1 into time;


                if time = ANY (select class_times
                               from class_times_in_minutes
                               where class_times >= (time_start_hr * 60 + time_start_min)
                                 and class_times <= (time_end_hr * 60 + time_end_min)) then
                    return true;
                else
                    return false;
                end if;


            end if;

        end loop;
    return false;
end;

$$;


ALTER FUNCTION public.is_time_conflicting(t1 integer, t2 integer) OWNER TO doadmin;

--
-- Name: login(text, text); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.login(id text, pass text) RETURNS basic_auth.jwt_token
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  _role name;
  result basic_auth.jwt_token;
begin
  -- check id and password
  select basic_auth.user_role(id, pass) into _role;
  if _role is null then
    raise invalid_password using message = 'invalid user or password';
  end if;

  select basic_auth.sign(
      row_to_json(r), '6cCALT5pL29Qs6tdhCpoVcrG3ZpsNnTm'
    ) as token
    from (
      select _role as role, login.id as id,
         extract(epoch from now())::integer + 60*60 as exp
    ) r
    into result;
  return result;
end;
$$;


ALTER FUNCTION public.login(id text, pass text) OWNER TO doadmin;

--
-- Name: on_hold(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.on_hold(id character varying, restricted_table character varying, operation character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

    return
        -- the person does not have an individual hold on the table with the given operation
                id in (select id
                       from individual_hold_members
                                INNER JOIN
                            individual_holds on individual_holds.hold_id = individual_hold_members.hold_id
                       where restricted_operation = operation
                         and restricted_table_or_view = restricted_table)
            OR
            -- the role is not in a hold on the table or view with the given operation
                ((current_user in (select role
                                  from role_holds
                                  where (restricted_table_or_view = restricted_table and
                                         restricted_operation = operation and active))) AND
                    -- or the person has been exempted from the hold
                not id in (select user_id
                           from role_holds
                                    inner join hold_exceptions he on role_holds.hold_id = he.hold_id
                           where (extract(epoch from date_created) + duration * 60 * 60) > (extract(epoch from now()))));
end;

$$;


ALTER FUNCTION public.on_hold(id character varying, restricted_table character varying, operation character varying) OWNER TO doadmin;

--
-- Name: quality_points(integer, character varying); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.quality_points(c_id integer, grade_gotten character varying) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
    DECLARE
        credits int;
        gpa float;
    BEGIN
    select credit_hours into credits from courses where courses.course_id = c_id;
    select gpa_points into gpa from grade_assignments where grade_assignments.grade = grade_gotten;
    if credits is null OR gpa is null then
    raise exception 'invalid course or grade' using hint = 'Please check your inputs';
    end if;
    return credits * gpa;

end;
$$;


ALTER FUNCTION public.quality_points(c_id integer, grade_gotten character varying) OWNER TO doadmin;

--
-- Name: student_course_registration(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.student_course_registration() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    if tg_op = 'INSERT' THEN
        CASE
            -- check if the student is on hold
            WHEN (on_hold(new.student_id, 'registration', 'insert'))
                then raise exception 'Student is on hold';
            --         check if the student has completed the pre-requisite requirements
--                 check whether the override query is working properly
            WHEN (new.section_id in (select se.section_id
                                     from student_enrollment se
                                              inner join sections s on se.section_id = s.section_id
                                              inner join session s2 on s.session_id = s2.session_id
                                              inner join courses c on c.course_id = s.course_id
                                     WHERE s2.status = 'active'
                                       and s2.state_id < 3
                                       and current_setting('request.jwt.claims', true)::json ->> 'id' =
                                           se.student_id))
                then raise exception 'Course is already registered';
            WHEN not (new.section_id in (select s.section_id
                                         from sections s
                                                  inner join session s2 on s.session_id = s2.session_id
                                         WHERE s2.status = 'active'
                                           and s2.state_id < 3))
                then raise exception 'Course is not available for registration';

            WHEN not ((are_prerequisites_satisfied(new.student_id, new.section_id))
                and
                      not (select distinct student_id
                           from overrides
                           where state = 'Accepted'
                             and student_id = new.student_id
                             and section_id = new.section_id
                             and override_type = 'Pre-requisite') = new.student_id)
                then raise exception 'Not all prerequisites satisfied' using hint = 'Check the prerequisites for the course';
            WHEN ((select distinct level from students where student_id = new.student_id)
                <>
                  (select level
                   from courses
                            inner join sections s on courses.course_id = s.course_id
                   where section_id = new.section_id)) and
                 not (select distinct student_id
                      from overrides
                      where state = 'Accepted'
                        and student_id = new.student_id
                        and section_id = new.section_id
                        and override_type = 'Level') = new.student_id
                then raise exception 'This course is not for the students level';
            WHEN (get_student_year(new.student_id) <> (select distinct min_student_year
                                                       from courses
                                                                inner join sections s2 on courses.course_id = s2.course_id
                                                       where s2.section_id = new.section_id)) and
                 not (select distinct student_id
                      from overrides
                      where state = 'Accepted'
                        and student_id = new.student_id
                        and section_id = new.section_id
                        and override_type = 'Min-Year') = new.student_id
                then raise exception 'Min-year not reached' using hint =
                        'Remove one of the conflicting courses first or request a min-level override';


            WHEN  conflicts_with_registration(new.section_id, current_setting('request.jwt.claims', true)::json ->> 'id')
                then raise exception 'Time conflict' using hint =
                        'Remove one of the conflicting courses first or request a time-conflict override';

            WHEN is_course_limit_reached(current_setting('request.jwt.claims', true)::json ->> 'id') then
                raise exception 'Max course limit reached' using hint = 'Request an overload to take additional sections';

            WHEN not (COALESCE((select distinct student_id
                      from overrides
                      where state = 'Accepted'
                        and student_id = current_setting('request.jwt.claims', true)::json ->> 'id'
                        and section_id = new.section_id
                        and override_type = 'Class-Size'),'') = current_setting('request.jwt.claims', true)::json ->> 'id')
                and is_class_full(new.section_id)
                then raise exception 'Class is full' using hint = 'Request a class size override to take this section';
            else INSERT INTO student_enrollment (section_id, student_id)

                 VALUES (new.section_id, current_setting('request.jwt.claims', true)::json ->> 'id');
                 return new;


            END CASE;
    elseif tg_op = 'DELETE' then
        if on_hold(new.student_id, 'registration', 'delete') then
            raise exception 'Cannot delete' using hint = 'On hold';
        end if;
        if (new.section_id not in (select se.section_id
                                   from student_enrollment se
                                            inner join sections s on se.section_id = s.section_id
                                            inner join session s2 on s.session_id = s2.session_id
                                            inner join courses c on c.course_id = s.course_id
                                   WHERE s2.status = 'active'
                                     and s2.state_id < 3
                                     and current_setting('request.jwt.claims', true)::json ->> 'id' =
                                         se.student_id)) then
            raise exception 'Section not registered' using hint = 'Cannot delete a section that is not registered';

        end if;
        delete
        from student_enrollment se
        where se.student_id = current_setting('request.jwt.claims', true)::json ->> 'id'
          and se.section_id = old.section_id;
        return old;

    end if;

end;
$$;


ALTER FUNCTION public.student_course_registration() OWNER TO doadmin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: users; Type: TABLE; Schema: basic_auth; Owner: doadmin
--

CREATE TABLE basic_auth.users (
    id text NOT NULL,
    pass text NOT NULL,
    role name NOT NULL,
    CONSTRAINT users_pass_check CHECK ((length(pass) < 512)),
    CONSTRAINT users_role_check CHECK ((length((role)::text) < 512))
);


ALTER TABLE basic_auth.users OWNER TO doadmin;

--
-- Name: class_dates_abbrev; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.class_dates_abbrev (
    class_abbrev_id integer NOT NULL,
    abbrev character varying(4)
);


ALTER TABLE public.class_dates_abbrev OWNER TO doadmin;

--
-- Name: class_times; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.class_times (
    class_time_id integer NOT NULL,
    str_rep text GENERATED ALWAYS AS ((((((((start_hour)::text || ':'::text) || (start_minute)::text) || ' - '::text) || (end_hour)::text) || ':'::text) || (end_minute)::text)) STORED,
    start_hour integer NOT NULL,
    start_minute integer NOT NULL,
    end_hour integer NOT NULL,
    end_minute integer NOT NULL,
    CONSTRAINT class_times_end_hour_check CHECK (((end_hour >= 0) AND (end_hour < 24))),
    CONSTRAINT class_times_end_minute_check CHECK (((end_minute >= 0) AND (end_minute < 60))),
    CONSTRAINT class_times_start_hour_check CHECK (((start_hour >= 0) AND (start_hour < 24))),
    CONSTRAINT class_times_start_minute_check CHECK (((start_minute >= 0) AND (start_minute < 60)))
);


ALTER TABLE public.class_times OWNER TO doadmin;

--
-- Name: courses; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.courses (
    course_id integer NOT NULL,
    title character varying(250) NOT NULL,
    category character varying(150) NOT NULL,
    level character varying,
    lab boolean NOT NULL,
    course_code character varying(7),
    credit_hours integer NOT NULL,
    min_student_year integer DEFAULT 1 NOT NULL,
    school_id integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.courses OWNER TO doadmin;

--
-- Name: faculty; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.faculty (
    faculty_id character varying(25) NOT NULL,
    date_of_birth date,
    date_of_emp date,
    school character varying(100) NOT NULL,
    department character varying(100) NOT NULL,
    email character varying(150) NOT NULL,
    address character varying(500),
    phone_no character varying(11),
    f_name character varying(20) NOT NULL,
    m_name character varying(20),
    l_name character varying(20) NOT NULL,
    status character varying(16) NOT NULL
);


ALTER TABLE public.faculty OWNER TO doadmin;

--
-- Name: faculty_assignment; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.faculty_assignment (
    fac_id character varying(50) NOT NULL,
    sid integer NOT NULL
);


ALTER TABLE public.faculty_assignment OWNER TO doadmin;

--
-- Name: section_times; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.section_times (
    section_time_id integer NOT NULL,
    class_dates_abbrev integer NOT NULL,
    class_time_id integer NOT NULL
);


ALTER TABLE public.section_times OWNER TO doadmin;

--
-- Name: sections; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.sections (
    section_id integer NOT NULL,
    course_id integer NOT NULL,
    session_id integer,
    location character varying(32),
    capacity integer,
    section_time_id integer NOT NULL,
    section_number integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.sections OWNER TO doadmin;

--
-- Name: session; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.session (
    session_id integer NOT NULL,
    semester character varying(16) NOT NULL,
    year integer NOT NULL,
    status character varying(16) DEFAULT 'disabled'::character varying NOT NULL,
    state_id integer NOT NULL,
    active boolean DEFAULT false NOT NULL,
    CONSTRAINT session_semester_check CHECK (((semester)::text = ANY ((ARRAY['Fall'::character varying, 'Spring'::character varying, 'Intersessional'::character varying])::text[]))),
    CONSTRAINT session_status_check CHECK (((status)::text = ANY ((ARRAY['disabled'::character varying, 'active'::character varying, 'closed'::character varying])::text[])))
);


ALTER TABLE public.session OWNER TO doadmin;

--
-- Name: student_enrollment; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.student_enrollment (
    section_id integer NOT NULL,
    student_id character varying(50) NOT NULL,
    grade character varying(2),
    student_enrollment_id integer NOT NULL
);


ALTER TABLE public.student_enrollment OWNER TO doadmin;

--
-- Name: all_sections; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.all_sections AS
 SELECT s.section_id,
    c.course_code,
    c.title,
    c.credit_hours,
    public.get_enrollment_number(se.section_id) AS enrolled,
    s.capacity,
    ((((f.f_name)::text || ' '::text) || COALESCE(((f.m_name)::text || ' '::text), ''::text)) || (f.l_name)::text) AS faculty,
    (((cda.abbrev)::text || ' '::text) || ct.str_rep) AS "time",
    s.location,
    (((s2.semester)::text || ' '::text) || s2.year) AS term,
    s2.session_id,
    s.section_number
   FROM ((((((((public.sections s
     JOIN public.session s2 ON ((s.session_id = s2.session_id)))
     JOIN public.courses c ON ((c.course_id = s.course_id)))
     FULL JOIN public.faculty_assignment fa ON ((s.section_id = fa.sid)))
     FULL JOIN public.faculty f ON (((f.faculty_id)::text = (fa.fac_id)::text)))
     JOIN public.section_times st ON ((s.section_time_id = st.section_time_id)))
     JOIN public.class_dates_abbrev cda ON ((st.class_dates_abbrev = cda.class_abbrev_id)))
     JOIN public.class_times ct ON ((ct.class_time_id = st.class_time_id)))
     LEFT JOIN public.student_enrollment se ON ((s.section_id = se.section_id)));


ALTER TABLE public.all_sections OWNER TO doadmin;

--
-- Name: class_dates; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.class_dates (
    class_dates_id integer NOT NULL,
    class_abbrev_id integer,
    day_id integer
);


ALTER TABLE public.class_dates OWNER TO doadmin;

--
-- Name: class_dates_abbrev_class_abbrev_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.class_dates_abbrev_class_abbrev_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.class_dates_abbrev_class_abbrev_id_seq OWNER TO doadmin;

--
-- Name: class_dates_abbrev_class_abbrev_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.class_dates_abbrev_class_abbrev_id_seq OWNED BY public.class_dates_abbrev.class_abbrev_id;


--
-- Name: class_dates_class_dates_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.class_dates_class_dates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.class_dates_class_dates_id_seq OWNER TO doadmin;

--
-- Name: class_dates_class_dates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.class_dates_class_dates_id_seq OWNED BY public.class_dates.class_dates_id;


--
-- Name: class_times_class_time_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.class_times_class_time_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.class_times_class_time_id_seq OWNER TO doadmin;

--
-- Name: class_times_class_time_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.class_times_class_time_id_seq OWNED BY public.class_times.class_time_id;


--
-- Name: class_times_in_minutes; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.class_times_in_minutes (
    class_times integer
);


ALTER TABLE public.class_times_in_minutes OWNER TO doadmin;

--
-- Name: concise_schedule; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.concise_schedule AS
 SELECT (((s2.semester)::text || ' '::text) || s2.year) AS term,
    c.course_code,
    c.title,
    s.section_id,
    c.lab,
    s.section_number,
    ((((f.f_name)::text || ' '::text) || COALESCE(((f.m_name)::text || ' '::text), ''::text)) || (f.l_name)::text) AS faculty,
    (((cda.abbrev)::text || ' '::text) || ct.str_rep) AS "time",
    s.location
   FROM ((((((((public.sections s
     JOIN public.session s2 ON ((s.session_id = s2.session_id)))
     JOIN public.courses c ON ((c.course_id = s.course_id)))
     JOIN public.faculty_assignment fa ON ((s.section_id = fa.sid)))
     JOIN public.faculty f ON (((f.faculty_id)::text = (fa.fac_id)::text)))
     JOIN public.section_times st ON ((s.section_time_id = st.section_time_id)))
     JOIN public.class_dates_abbrev cda ON ((st.class_dates_abbrev = cda.class_abbrev_id)))
     JOIN public.class_times ct ON ((ct.class_time_id = st.class_time_id)))
     JOIN public.student_enrollment se ON ((s.section_id = se.section_id)))
  WHERE (((se.student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)) AND ((s2.status)::text = 'active'::text) AND (s2.state_id > 2));


ALTER TABLE public.concise_schedule OWNER TO doadmin;

--
-- Name: days; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.days (
    day_id integer NOT NULL,
    day_of_the_week character varying(16)
);


ALTER TABLE public.days OWNER TO doadmin;

--
-- Name: days_day_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.days_day_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.days_day_id_seq OWNER TO doadmin;

--
-- Name: days_day_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.days_day_id_seq OWNED BY public.days.day_id;


--
-- Name: students; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.students (
    student_id character varying(50) NOT NULL,
    status character varying(50) NOT NULL,
    date_of_birth date NOT NULL,
    date_of_admission date NOT NULL,
    level character varying(15) NOT NULL,
    major character varying(100) NOT NULL,
    minor character varying(100),
    concentration character varying(100),
    school integer NOT NULL,
    address character varying(500) NOT NULL,
    password character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    phone_number character varying(11),
    first_name character varying(50) NOT NULL,
    middle_name character varying(50),
    last_name character varying(50) NOT NULL,
    term_of_admission integer,
    program_id integer,
    gender character varying(8) DEFAULT 'Male'::character varying NOT NULL,
    state_of_origin character varying(16) DEFAULT 'Adamawa'::character varying NOT NULL,
    lga character varying(16) DEFAULT 'Yola'::character varying NOT NULL,
    CONSTRAINT students_gender_check CHECK (((gender)::text = ANY ((ARRAY['Male'::character varying, 'Female'::character varying])::text[])))
);


ALTER TABLE public.students OWNER TO doadmin;

--
-- Name: enrollments; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.enrollments AS
 SELECT students.student_id,
    ((((students.first_name)::text || ' '::text) || COALESCE(((students.middle_name)::text || ' '::text), ''::text)) || (students.last_name)::text) AS name,
    ((((f.f_name)::text || ' '::text) || COALESCE(((f.m_name)::text || ' '::text), ''::text)) || (f.l_name)::text) AS faculty,
    (((ses.semester)::text || ' '::text) || ses.year) AS session,
    ses.session_id,
    se.grade,
    c.course_code,
    c.title,
    c.credit_hours
   FROM ((((((public.students
     JOIN public.student_enrollment se ON (((students.student_id)::text = (se.student_id)::text)))
     JOIN public.sections s ON ((s.section_id = se.section_id)))
     JOIN public.session ses ON ((ses.session_id = s.session_id)))
     JOIN public.courses c ON ((c.course_id = s.course_id)))
     JOIN public.faculty_assignment fa ON ((s.section_id = fa.sid)))
     JOIN public.faculty f ON (((fa.fac_id)::text = (f.faculty_id)::text)))
  WHERE ((((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text) = (students.student_id)::text) AND (NOT public.on_hold((((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text))::character varying, 'enrollments'::character varying, 'select'::character varying)) AND ((ses.status)::text <> 'active'::text));


ALTER TABLE public.enrollments OWNER TO doadmin;

--
-- Name: faculty_schedule; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.faculty_schedule AS
 SELECT (((s2.semester)::text || ' '::text) || s2.year) AS session,
    c.course_code,
    c.title,
    s.section_id,
    s.section_number,
    s.location
   FROM ((((public.sections s
     JOIN public.faculty_assignment fa ON ((s.section_id = fa.sid)))
     JOIN public.faculty f ON (((f.faculty_id)::text = (fa.fac_id)::text)))
     JOIN public.courses c ON ((c.course_id = s.course_id)))
     JOIN public.session s2 ON ((s2.session_id = s.session_id)))
  WHERE (((f.faculty_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)) AND ((s2.status)::text = 'active'::text) AND (s2.state_id > 2));


ALTER TABLE public.faculty_schedule OWNER TO doadmin;

--
-- Name: grade_assignments; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.grade_assignments (
    id integer NOT NULL,
    grade character varying(2),
    gpa_points real,
    count_gpa boolean
);


ALTER TABLE public.grade_assignments OWNER TO doadmin;

--
-- Name: grade_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.grade_assignments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.grade_assignments_id_seq OWNER TO doadmin;

--
-- Name: grade_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.grade_assignments_id_seq OWNED BY public.grade_assignments.id;


--
-- Name: hold_exceptions; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.hold_exceptions (
    table_id integer NOT NULL,
    user_id text NOT NULL,
    duration integer DEFAULT 24 NOT NULL,
    hold_id integer NOT NULL,
    date_created date DEFAULT now(),
    CONSTRAINT hold_exceptions_duration_check CHECK (((duration > 0) AND (duration <= 100)))
);


ALTER TABLE public.hold_exceptions OWNER TO doadmin;

--
-- Name: hold_exceptions_table_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.hold_exceptions_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.hold_exceptions_table_id_seq OWNER TO doadmin;

--
-- Name: hold_exceptions_table_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.hold_exceptions_table_id_seq OWNED BY public.hold_exceptions.table_id;


--
-- Name: individual_hold_members; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.individual_hold_members (
    hold_id integer NOT NULL,
    member_id text NOT NULL
);


ALTER TABLE public.individual_hold_members OWNER TO doadmin;

--
-- Name: individual_holds; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.individual_holds (
    hold_id integer NOT NULL,
    hold_name character varying(16) NOT NULL,
    restricted_operation character varying(16) NOT NULL,
    restricted_table_or_view character varying(16),
    active boolean,
    CONSTRAINT individual_holds_restricted_operation_check CHECK (((restricted_operation)::text = ANY ((ARRAY['select'::character varying, 'delete'::character varying, 'update'::character varying, 'insert'::character varying])::text[])))
);


ALTER TABLE public.individual_holds OWNER TO doadmin;

--
-- Name: individual_holds_hold_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.individual_holds_hold_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_holds_hold_id_seq OWNER TO doadmin;

--
-- Name: individual_holds_hold_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.individual_holds_hold_id_seq OWNED BY public.individual_holds.hold_id;


--
-- Name: location; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.location (
    location_id integer NOT NULL,
    location integer NOT NULL,
    building character varying(150) NOT NULL
);


ALTER TABLE public.location OWNER TO doadmin;

--
-- Name: max_courses; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.max_courses (
    id integer NOT NULL,
    school integer NOT NULL,
    max integer DEFAULT 6 NOT NULL
);


ALTER TABLE public.max_courses OWNER TO doadmin;

--
-- Name: max_courses_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.max_courses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.max_courses_id_seq OWNER TO doadmin;

--
-- Name: max_courses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.max_courses_id_seq OWNED BY public.max_courses.id;


--
-- Name: overloads; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.overloads (
    overload_id integer NOT NULL,
    student_id character varying NOT NULL,
    session_id integer NOT NULL,
    state character varying(8) DEFAULT 'Posted'::character varying NOT NULL,
    additional_courses integer DEFAULT 1 NOT NULL,
    notes character varying,
    date date DEFAULT now(),
    CONSTRAINT overloads_state_check CHECK (((state)::text = ANY ((ARRAY['Posted'::character varying, 'Accepted'::character varying, 'Rejected'::character varying])::text[])))
);


ALTER TABLE public.overloads OWNER TO doadmin;

--
-- Name: overloads_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.overloads_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.overloads_id_seq OWNER TO doadmin;

--
-- Name: overloads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.overloads_id_seq OWNED BY public.overloads.overload_id;


--
-- Name: overrides; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.overrides (
    override_id integer NOT NULL,
    section_id integer,
    student_id character varying,
    override_type character varying,
    state character varying(16) DEFAULT 'Posted'::character varying,
    date date DEFAULT now() NOT NULL,
    session_id integer NOT NULL,
    CONSTRAINT overrides_override_type_check CHECK (((override_type)::text = ANY ((ARRAY['Pre-requisite'::character varying, 'Level'::character varying, 'Time-Conflict'::character varying, 'Class-Size'::character varying, 'Min-Year'::character varying])::text[]))),
    CONSTRAINT overrides_state_check CHECK (((state)::text = ANY ((ARRAY['Posted'::character varying, 'Rejected'::character varying, 'Accepted'::character varying])::text[])))
);


ALTER TABLE public.overrides OWNER TO doadmin;

--
-- Name: overrides_override_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.overrides_override_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.overrides_override_id_seq OWNER TO doadmin;

--
-- Name: overrides_override_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.overrides_override_id_seq OWNED BY public.overrides.override_id;


--
-- Name: prerequisites; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.prerequisites (
    course_id integer NOT NULL,
    pre_req_course_id integer NOT NULL
);


ALTER TABLE public.prerequisites OWNER TO doadmin;

--
-- Name: programs; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.programs (
    program_id integer NOT NULL,
    program_name character varying NOT NULL,
    program_chair_id integer,
    level character varying,
    CONSTRAINT programs_level_check CHECK (((level)::text = ANY ((ARRAY['Undergraduate'::character varying, 'Graduate'::character varying])::text[])))
);


ALTER TABLE public.programs OWNER TO doadmin;

--
-- Name: programs_program_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.programs_program_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.programs_program_id_seq OWNER TO doadmin;

--
-- Name: programs_program_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.programs_program_id_seq OWNED BY public.programs.program_id;


--
-- Name: registration; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.registration AS
 SELECT se.student_id,
    se.section_id,
    c.course_code,
    c.title,
    c.credit_hours,
    public.get_enrollment_number(se.section_id) AS enrolled,
    s.capacity,
    ((((f.f_name)::text || ' '::text) || COALESCE(((f.m_name)::text || ' '::text), ''::text)) || (f.l_name)::text) AS faculty,
    (((cda.abbrev)::text || ' '::text) || ct.str_rep) AS "time"
   FROM ((((((((public.sections s
     JOIN public.session s2 ON ((s.session_id = s2.session_id)))
     JOIN public.courses c ON ((c.course_id = s.course_id)))
     FULL JOIN public.faculty_assignment fa ON ((s.section_id = fa.sid)))
     FULL JOIN public.faculty f ON (((f.faculty_id)::text = (fa.fac_id)::text)))
     JOIN public.section_times st ON ((s.section_time_id = st.section_time_id)))
     JOIN public.class_dates_abbrev cda ON ((st.class_dates_abbrev = cda.class_abbrev_id)))
     JOIN public.class_times ct ON ((ct.class_time_id = st.class_time_id)))
     JOIN public.student_enrollment se ON ((s.section_id = se.section_id)))
  WHERE (((s2.status)::text = 'active'::text) AND (s2.state_id < 3) AND (((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text) = (se.student_id)::text));


ALTER TABLE public.registration OWNER TO doadmin;

--
-- Name: role_holds; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.role_holds (
    hold_id integer NOT NULL,
    hold_name character varying(32) NOT NULL,
    role name NOT NULL,
    restricted_operation character varying(16) NOT NULL,
    restricted_table_or_view character varying(16),
    active boolean,
    CONSTRAINT role_holds_restricted_operation_check CHECK (((restricted_operation)::text = ANY ((ARRAY['select'::character varying, 'delete'::character varying, 'update'::character varying, 'insert'::character varying])::text[])))
);


ALTER TABLE public.role_holds OWNER TO doadmin;

--
-- Name: role_holds_hold_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.role_holds_hold_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.role_holds_hold_id_seq OWNER TO doadmin;

--
-- Name: role_holds_hold_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.role_holds_hold_id_seq OWNED BY public.role_holds.hold_id;


--
-- Name: schools; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.schools (
    school_id integer NOT NULL,
    school_name character varying NOT NULL,
    dean character varying
);


ALTER TABLE public.schools OWNER TO doadmin;

--
-- Name: schools_school_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.schools_school_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.schools_school_id_seq OWNER TO doadmin;

--
-- Name: schools_school_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.schools_school_id_seq OWNED BY public.schools.school_id;


--
-- Name: section_times_section_time_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.section_times_section_time_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.section_times_section_time_id_seq OWNER TO doadmin;

--
-- Name: section_times_section_time_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.section_times_section_time_id_seq OWNED BY public.section_times.section_time_id;


--
-- Name: sections_section_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

ALTER TABLE public.sections ALTER COLUMN section_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sections_section_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: session_session_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.session_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.session_session_id_seq OWNER TO doadmin;

--
-- Name: session_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.session_session_id_seq OWNED BY public.session.session_id;


--
-- Name: session_state_holds; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.session_state_holds (
    session_state_id integer NOT NULL,
    hold_id integer NOT NULL,
    hold_status boolean NOT NULL
);


ALTER TABLE public.session_state_holds OWNER TO doadmin;

--
-- Name: session_states; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.session_states (
    state_id integer NOT NULL,
    state_name character varying(32) NOT NULL
);


ALTER TABLE public.session_states OWNER TO doadmin;

--
-- Name: session_states_state_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.session_states_state_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.session_states_state_id_seq OWNER TO doadmin;

--
-- Name: session_states_state_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.session_states_state_id_seq OWNED BY public.session_states.state_id;


--
-- Name: settings; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.settings (
    jwt_expiry integer DEFAULT 60 NOT NULL,
    credit_price double precision DEFAULT 95000 NOT NULL
);


ALTER TABLE public.settings OWNER TO doadmin;

--
-- Name: student_data; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.student_data AS
 SELECT students.student_id,
    students.status,
    students.date_of_birth,
    students.date_of_admission,
    students.level,
    students.major,
    students.minor,
    students.concentration,
    schools.school_name,
    (((s.semester)::text || ' '::text) || s.year) AS term_of_admission,
    ((((students.first_name)::text || ' '::text) || COALESCE(((students.middle_name)::text || ' '::text), ''::text)) || (students.last_name)::text) AS name,
    students.first_name,
    students.middle_name,
    students.last_name,
    students.address,
    students.email,
    students.phone_number,
    students.gender,
    p.program_name AS degree,
    public.get_earned_hours(students.student_id) AS earned_hours,
    public.get_attempted_hours(students.student_id) AS attempted_hours,
    public.get_student_year(students.student_id) AS year,
    public.get_total_quality_points((students.student_id)::text) AS quality_points,
    public.get_cgpa((students.student_id)::text) AS cgpa
   FROM (((public.students
     JOIN public.session s ON ((s.session_id = students.term_of_admission)))
     JOIN public.schools ON ((students.school = schools.school_id)))
     JOIN public.programs p ON ((students.program_id = p.program_id)))
  WHERE ((students.student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text));


ALTER TABLE public.student_data OWNER TO doadmin;

--
-- Name: student_enrollment_student_enrollment_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.student_enrollment_student_enrollment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.student_enrollment_student_enrollment_id_seq OWNER TO doadmin;

--
-- Name: student_enrollment_student_enrollment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.student_enrollment_student_enrollment_id_seq OWNED BY public.student_enrollment.student_enrollment_id;


--
-- Name: student_year_per_program; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.student_year_per_program (
    program_id integer NOT NULL,
    year_id integer NOT NULL,
    from_credits integer NOT NULL,
    to_credits integer NOT NULL
);


ALTER TABLE public.student_year_per_program OWNER TO doadmin;

--
-- Name: student_years; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.student_years (
    year_id integer NOT NULL,
    year_name character varying NOT NULL
);


ALTER TABLE public.student_years OWNER TO doadmin;

--
-- Name: students_enrolled; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.students_enrolled AS
 SELECT s.section_id,
    se.student_id,
    s.session_id,
    fa.fac_id,
    c.course_id
   FROM (((((public.student_enrollment se
     JOIN public.sections s ON ((s.section_id = se.section_id)))
     JOIN public.faculty_assignment fa ON ((s.section_id = fa.sid)))
     JOIN public.faculty f ON (((f.faculty_id)::text = (fa.fac_id)::text)))
     JOIN public.session s2 ON ((s2.session_id = s.session_id)))
     JOIN public.courses c ON ((c.course_id = s.course_id)))
  WHERE ((fa.fac_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text));


ALTER TABLE public.students_enrolled OWNER TO doadmin;

--
-- Name: t_amount; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.t_amount (
    "?column?" double precision
);


ALTER TABLE public.t_amount OWNER TO doadmin;

--
-- Name: test; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.test (
    name character varying(64),
    number integer
);


ALTER TABLE public.test OWNER TO doadmin;

--
-- Name: transaction; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.transaction (
    student_id character varying(50) NOT NULL,
    transaction_type character varying(50) NOT NULL,
    description character varying(300) NOT NULL,
    date date DEFAULT now() NOT NULL,
    amount double precision NOT NULL,
    transaction_id integer NOT NULL,
    session_id integer,
    CONSTRAINT debit_credit_check CHECK (((transaction_type)::text = ANY ((ARRAY['credit'::character varying, 'debit'::character varying])::text[])))
);


ALTER TABLE public.transaction OWNER TO doadmin;

--
-- Name: transaction_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: doadmin
--

CREATE SEQUENCE public.transaction_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.transaction_transaction_id_seq OWNER TO doadmin;

--
-- Name: transaction_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: doadmin
--

ALTER SEQUENCE public.transaction_transaction_id_seq OWNED BY public.transaction.transaction_id;


--
-- Name: class_dates class_dates_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_dates ALTER COLUMN class_dates_id SET DEFAULT nextval('public.class_dates_class_dates_id_seq'::regclass);


--
-- Name: class_dates_abbrev class_abbrev_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_dates_abbrev ALTER COLUMN class_abbrev_id SET DEFAULT nextval('public.class_dates_abbrev_class_abbrev_id_seq'::regclass);


--
-- Name: class_times class_time_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_times ALTER COLUMN class_time_id SET DEFAULT nextval('public.class_times_class_time_id_seq'::regclass);


--
-- Name: days day_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.days ALTER COLUMN day_id SET DEFAULT nextval('public.days_day_id_seq'::regclass);


--
-- Name: grade_assignments id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.grade_assignments ALTER COLUMN id SET DEFAULT nextval('public.grade_assignments_id_seq'::regclass);


--
-- Name: hold_exceptions table_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.hold_exceptions ALTER COLUMN table_id SET DEFAULT nextval('public.hold_exceptions_table_id_seq'::regclass);


--
-- Name: individual_holds hold_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.individual_holds ALTER COLUMN hold_id SET DEFAULT nextval('public.individual_holds_hold_id_seq'::regclass);


--
-- Name: max_courses id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.max_courses ALTER COLUMN id SET DEFAULT nextval('public.max_courses_id_seq'::regclass);


--
-- Name: overloads overload_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overloads ALTER COLUMN overload_id SET DEFAULT nextval('public.overloads_id_seq'::regclass);


--
-- Name: overrides override_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overrides ALTER COLUMN override_id SET DEFAULT nextval('public.overrides_override_id_seq'::regclass);


--
-- Name: programs program_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.programs ALTER COLUMN program_id SET DEFAULT nextval('public.programs_program_id_seq'::regclass);


--
-- Name: role_holds hold_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.role_holds ALTER COLUMN hold_id SET DEFAULT nextval('public.role_holds_hold_id_seq'::regclass);


--
-- Name: schools school_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.schools ALTER COLUMN school_id SET DEFAULT nextval('public.schools_school_id_seq'::regclass);


--
-- Name: section_times section_time_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.section_times ALTER COLUMN section_time_id SET DEFAULT nextval('public.section_times_section_time_id_seq'::regclass);


--
-- Name: session session_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session ALTER COLUMN session_id SET DEFAULT nextval('public.session_session_id_seq'::regclass);


--
-- Name: session_states state_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session_states ALTER COLUMN state_id SET DEFAULT nextval('public.session_states_state_id_seq'::regclass);


--
-- Name: student_enrollment student_enrollment_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_enrollment ALTER COLUMN student_enrollment_id SET DEFAULT nextval('public.student_enrollment_student_enrollment_id_seq'::regclass);


--
-- Name: transaction transaction_id; Type: DEFAULT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.transaction ALTER COLUMN transaction_id SET DEFAULT nextval('public.transaction_transaction_id_seq'::regclass);


--
-- Data for Name: users; Type: TABLE DATA; Schema: basic_auth; Owner: doadmin
--

COPY basic_auth.users (id, pass, role) FROM stdin;
A00021247	$2a$06$mFmy5x5ty/dSKybRW9CgFOMhHyUSA.QtdMj40mWB4YwCN1xlrPPD2	student
A00021524	$2a$06$QiytCVyH2u.ltAELAGg0vOGUAqjoS.nELM9K2kLLM7K4PJjjPAP6.	student
A00021759	$2a$06$j9nWc5QV9B3kCN7VruYHPOimghfJHCsLQfSlnPuIWml3IH9ubYtd6	student
A00021606	$2a$06$E.gLnbgOCM3PPRySStlDv.D.oIko2fP03PRV.E9slWmCGUKIBtIQe	student
A00021186	$2a$06$AJk0pFMdvbPHBz8U/r6mOOpP11AphhSXMiSAsjymYVLvnzp1n5Lja	student
A00021874	$2a$06$O2MUooGAEFtcVmwAThX6o.0lOp5pIXChfgxf5S44FajXg2DNm4Q.O	student
A00021976	$2a$06$omh1tiAOTa6v9LAmuixa0OjS.DhRwwFE2DFsnEj07Pa7Z/ckw4wuK	student
A00021298	$2a$06$Da2T9a.S9ku/bkYfgrm8reQAUPxzueyKOCHZvEG0qi3yft.DO6rHC	student
A00021204	$2a$06$bPYRJ4Gybu0/M7ueluOEiuGXtQnGILoQyI6LmFpaVdNY5x1lcqd4i	student
A00021110	$2a$06$G/1dfkkvmNFa3iJGsJyUxeyoZyWm0CW9PqMN5h48AJEB/Aamh1erm	student
AS0394622	$2a$06$MVL5LiF9wDP6BiZf5JUOA.1IzHBpNZZxDjiQXFubtoYKf/SFRTjm6	faculty
AS3243154	$2a$06$liTFpmn4VA69viJdtmOEvevdXBNMxyek6W0dYYmGy/qJ46aOnzDxa	faculty
AS9680641	$2a$06$y0J1YxAJm3jA44xJIWaa.eic97uTOHMWISHtnNCeO7lnaPU8swbnC	faculty
AS3365359	$2a$06$3G95dz2NJh74gVZdV/GibOCVK3O5WX54vmlHY99JuB3RywlXatEl.	faculty
AS5947201	$2a$06$vCCCU0SvGorIeVYrIoFFjuInbmarElXNgZhOW/Bb9ndWLvh9t4R6a	faculty
AS8135925	$2a$06$3hvt11Neac7oHfOFrmJCrOY1xO4cRzcCIV50fk.zZSY9fvpmwxDvy	faculty
AS6898854	$2a$06$Mub.8v4mRHn5pjdSmn1r6usuSz8xNWSaYinfpYcde3Na0HeeLtZVW	faculty
AS4030545	$2a$06$cKjC1PwD8h702URkH7yZWeBzauXSJukUBDBW30QZyeZY.DJhfdnfe	faculty
AS9752922	$2a$06$HA0PglArUaBLkd9IeEBDfuBS7wGy8/3wz2p39S3Q87VKL2x/ANTni	faculty
AS1153698	$2a$06$9OhIYZ.W/dfHf/hNsxIcsu8Ux.HA3LVH0aSzx8GIH2AkprkuNmSq2	faculty
\.


--
-- Data for Name: class_dates; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.class_dates (class_dates_id, class_abbrev_id, day_id) FROM stdin;
1	1	1
2	1	3
3	2	2
4	2	4
5	3	5
6	4	1
7	4	3
8	4	5
\.


--
-- Data for Name: class_dates_abbrev; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.class_dates_abbrev (class_abbrev_id, abbrev) FROM stdin;
1	MW
2	TR
3	F
4	MWF
\.


--
-- Data for Name: class_times; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.class_times (class_time_id, start_hour, start_minute, end_hour, end_minute) FROM stdin;
1	1	15	2	45
2	3	0	4	30
3	8	0	9	30
4	9	45	11	15
5	3	0	6	0
6	1	0	2	0
\.


--
-- Data for Name: class_times_in_minutes; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.class_times_in_minutes (class_times) FROM stdin;
0
5
10
15
20
25
30
35
40
45
50
55
60
65
70
75
80
85
90
95
100
105
110
115
120
125
130
135
140
145
150
155
160
165
170
175
180
185
190
195
200
205
210
215
220
225
230
235
240
245
250
255
260
265
270
275
280
285
290
295
300
305
310
315
320
325
330
335
340
345
350
355
360
365
370
375
380
385
390
395
400
405
410
415
420
425
430
435
440
445
450
455
460
465
470
475
480
485
490
495
500
505
510
515
520
525
530
535
540
545
550
555
560
565
570
575
580
585
590
595
600
605
610
615
620
625
630
635
640
645
650
655
660
665
670
675
680
685
690
695
700
705
710
715
720
725
730
735
740
745
750
755
760
765
770
775
780
785
790
795
800
805
810
815
820
825
830
835
840
845
850
855
860
865
870
875
880
885
890
895
900
905
910
915
920
925
930
935
940
945
950
955
960
965
970
975
980
985
990
995
1000
1005
1010
1015
1020
1025
1030
1035
1040
1045
1050
1055
1060
1065
1070
1075
1080
1085
1090
1095
1100
1105
1110
1115
1120
1125
1130
1135
1140
1145
1150
1155
1160
1165
1170
1175
1180
1185
1190
1195
1200
1205
1210
1215
1220
1225
1230
1235
1240
1245
1250
1255
1260
1265
1270
1275
1280
1285
1290
1295
1300
1305
1310
1315
1320
1325
1330
1335
1340
1345
1350
1355
1360
1365
1370
1375
1380
1385
1390
1395
1400
1405
1410
1415
1420
1425
1430
1435
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.courses (course_id, title, category, level, lab, course_code, credit_hours, min_student_year, school_id) FROM stdin;
326397368	WLM	Major	Undergraduate	f	CSC 301	3	1	1
146162475	RTU	Major	Undergraduate	f	CSC 876	3	1	1
515472798	Yoga	Major	Undergraduate	f	CSC 092	3	1	1
280099426	XSD	Major	Undergraduate	f	CSC 580	3	1	1
190516729	JTAPI	Major	Undergraduate	f	CSC 174	3	1	1
602765844	HTML Scripting	Major	Undergraduate	f	CSC 422	3	1	1
5088799	Get Along Well with Others	Major	Undergraduate	f	CSC 108	3	1	1
213888523	Youth At Risk	Major	Undergraduate	f	CSC 625	3	1	1
856670399	Ion	Major	Undergraduate	f	CSC 302	3	1	1
848324025	CNN Pathfire	Major	Undergraduate	f	CSC 833	3	1	1
\.


--
-- Data for Name: days; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.days (day_id, day_of_the_week) FROM stdin;
1	Monday
2	Tuesday
3	Wednesday
4	Thursday
5	Friday
6	Saturday
7	Sunday
\.


--
-- Data for Name: faculty; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.faculty (faculty_id, date_of_birth, date_of_emp, school, department, email, address, phone_no, f_name, m_name, l_name, status) FROM stdin;
AS0394622	1978-11-02	2010-06-21	School of IT and Computing	Computer Science	ldumke0@people.com.cn	5317 Karstens Circle	08083881704	Lynne	Laurélie	Dumke	active
AS3243154	1988-06-12	2011-05-29	School of IT and Computing	Computer Science	aturmell1@sakura.ne.jp	9 Blackbird Center	08025061630	Adamo	Léonore	Turmell	active
AS9680641	1946-12-06	2005-05-04	School of IT and Computing	Computer Science	rbocking2@amazonaws.com	74 Rowland Junction	08068598330	Rahel	\N	Bocking	active
AS3365359	1942-03-01	2020-10-14	School of IT and Computing	Computer Science	ccoxhell3@xinhuanet.com	70139 Hanover Crossing	08007719705	Cleavland	\N	Coxhell	active
AS5947201	1972-06-30	2003-07-25	School of IT and Computing	Computer Science	nrivaland4@tmall.com	9352 Hanover Center	08032385379	Nerita	\N	Rivaland	active
AS8135925	1973-08-24	2019-11-07	School of IT and Computing	Computer Science	soughtright5@topsy.com	4 Old Shore Parkway	08071615647	Stearne	\N	Oughtright	active
AS6898854	1990-01-18	2009-09-08	School of IT and Computing	Computer Science	hkittel6@myspace.com	29554 Clyde Gallagher Hill	08012489695	Heindrick	\N	Kittel	active
AS4030545	1951-05-14	2008-10-25	School of IT and Computing	Computer Science	rjennaway7@google.fr	3 Express Terrace	08066888469	Raffaello	Ruì	Jennaway	active
AS9752922	1959-11-27	2015-12-27	School of IT and Computing	Computer Science	eemptage8@berkeley.edu	525 Eastlawn Circle	08073001592	Ephrem	Inès	Emptage	active
AS1153698	1974-10-24	2019-06-29	School of IT and Computing	Computer Science	bdecruce9@timesonline.co.uk	12 Orin Road	08098936685	Brigg	\N	De Cruce	active
\.


--
-- Data for Name: faculty_assignment; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.faculty_assignment (fac_id, sid) FROM stdin;
AS6898854	1
AS9752922	2
AS9752922	3
AS0394622	4
AS0394622	5
AS4030545	6
AS9680641	7
AS9752922	8
AS6898854	9
AS0394622	10
AS8135925	11
AS1153698	12
AS8135925	13
AS5947201	14
AS8135925	15
AS5947201	16
AS4030545	17
AS9752922	18
AS1153698	19
AS6898854	21
AS3365359	52
AS5947201	53
AS9680641	54
AS5947201	55
AS1153698	56
AS8135925	57
AS5947201	58
AS3243154	59
AS4030545	60
AS4030545	61
AS9752922	62
AS9752922	63
AS4030545	64
AS8135925	65
AS9752922	66
AS5947201	67
AS4030545	68
AS6898854	69
AS1153698	70
AS8135925	71
AS9752922	72
AS6898854	73
AS5947201	74
AS5947201	75
AS0394622	76
AS5947201	77
AS8135925	78
AS0394622	79
AS4030545	80
AS9752922	81
AS1153698	20
\.


--
-- Data for Name: grade_assignments; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.grade_assignments (id, grade, gpa_points, count_gpa) FROM stdin;
1	A	4	t
2	A-	3.7	t
3	B+	3.3	t
4	B	3	t
5	B-	2.7	t
6	C+	2.3	t
7	C	2	t
8	D	1	t
9	F	0	t
10	I	0	f
11	WP	0	f
12	WF	0	t
13	F	0	f
14	P	0	f
\.


--
-- Data for Name: hold_exceptions; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.hold_exceptions (table_id, user_id, duration, hold_id, date_created) FROM stdin;
4	A00021204	24	2	2022-10-14
\.


--
-- Data for Name: individual_hold_members; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.individual_hold_members (hold_id, member_id) FROM stdin;
\.


--
-- Data for Name: individual_holds; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.individual_holds (hold_id, hold_name, restricted_operation, restricted_table_or_view, active) FROM stdin;
\.


--
-- Data for Name: location; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.location (location_id, location, building) FROM stdin;
\.


--
-- Data for Name: max_courses; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.max_courses (id, school, max) FROM stdin;
2	1	6
\.


--
-- Data for Name: overloads; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.overloads (overload_id, student_id, session_id, state, additional_courses, notes, date) FROM stdin;
3	A00021204	5	Posted	1	Please help my life	2022-11-01
\.


--
-- Data for Name: overrides; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.overrides (override_id, section_id, student_id, override_type, state, date, session_id) FROM stdin;
4	84	A00021204	Class-Size	Posted	2022-11-01	5
5	86	A00021110	Class-Size	Accepted	2022-11-03	5
\.


--
-- Data for Name: prerequisites; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.prerequisites (course_id, pre_req_course_id) FROM stdin;
\.


--
-- Data for Name: programs; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.programs (program_id, program_name, program_chair_id, level) FROM stdin;
1	Bsc - Bachelor of Science	\N	Undergraduate
\.


--
-- Data for Name: role_holds; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.role_holds (hold_id, hold_name, role, restricted_operation, restricted_table_or_view, active) FROM stdin;
1	Enrollment hold	student	select	registration	f
2	Enrollments view hold	student	select	enrollments	f
3	Registration hold	student	insert	registration	f
\.


--
-- Data for Name: schools; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.schools (school_id, school_name, dean) FROM stdin;
1	School of IT and Computing	\N
\.


--
-- Data for Name: section_times; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.section_times (section_time_id, class_dates_abbrev, class_time_id) FROM stdin;
1	1	1
2	1	2
3	1	3
4	2	1
5	2	2
6	3	2
7	3	4
8	4	5
\.


--
-- Data for Name: sections; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.sections (section_id, course_id, session_id, location, capacity, section_time_id, section_number) FROM stdin;
52	326397368	2	Classroom 20	21	1	1
53	326397368	3	Classroom 18	42	4	1
54	326397368	4	Classroom 17	36	5	1
55	146162475	2	Classroom 18	21	3	1
56	146162475	3	Classroom 4	23	6	1
57	146162475	4	Classroom 12	46	1	1
58	515472798	2	Classroom 5	49	1	1
59	515472798	3	Classroom 18	46	1	1
60	515472798	4	Classroom 7	41	6	1
61	280099426	2	Classroom 3	29	1	1
62	280099426	3	Classroom 17	40	7	1
63	280099426	4	Classroom 8	32	8	1
64	190516729	2	Classroom 5	47	1	1
65	190516729	3	Classroom 12	39	5	1
66	190516729	4	Classroom 7	39	1	1
67	602765844	2	Classroom 19	39	4	1
68	602765844	3	Classroom 2	27	4	1
69	602765844	4	Classroom 15	48	6	1
70	5088799	2	Classroom 11	34	4	1
71	5088799	3	Classroom 17	21	4	1
72	5088799	4	Classroom 16	29	4	1
1	848324025	1	Classroom 33	49	1	1
2	146162475	1	Classroom 34	84	1	1
3	848324025	1	Classroom 17	28	1	1
4	848324025	1	Classroom 59	73	1	1
6	848324025	1	Classroom 78	20	2	1
7	190516729	1	Classroom 81	46	2	1
8	848324025	1	Classroom 40	61	2	1
9	602765844	1	Classroom 32	23	2	1
11	602765844	1	Classroom 28	85	3	1
12	848324025	1	Classroom 35	75	3	1
13	848324025	1	Classroom 29	16	3	1
14	848324025	1	Classroom 22	89	3	1
16	602765844	1	Classroom 26	3	4	1
17	848324025	1	Classroom 97	67	4	1
18	848324025	1	Classroom 63	91	4	1
19	602765844	1	Classroom 07	86	4	1
5	190516729	1	Classroom 90	9	5	1
10	190516729	1	Classroom 59	65	5	1
15	190516729	1	Classroom 09	73	5	1
20	848324025	1	Classroom 45	63	5	1
21	602765844	1	Classroom 38	90	6	1
73	213888523	2	Classroom 6	33	4	1
74	213888523	3	Classroom 15	20	2	1
75	213888523	4	Classroom 7	37	1	1
76	856670399	2	Classroom 7	40	7	1
77	856670399	3	Classroom 8	41	2	1
78	856670399	4	Classroom 1	50	7	1
79	848324025	2	Classroom 4	33	1	1
80	848324025	3	Classroom 12	24	3	1
81	848324025	4	Classroom 9	46	7	1
82	326397368	5	Classroom 18	10	2	1
83	280099426	5	Classroom 11	10	1	1
84	515472798	5	Classroom 16	10	2	1
85	280099426	5	Classroom 11	10	2	1
86	280099426	5	Classroom 15	1	1	1
\.


--
-- Data for Name: session; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.session (session_id, semester, year, status, state_id, active) FROM stdin;
2	Spring	2021	closed	1	f
3	Fall	2021	closed	1	f
5	Spring	2023	active	1	f
4	Spring	2022	closed	3	f
1	Fall	2022	active	3	t
\.


--
-- Data for Name: session_state_holds; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.session_state_holds (session_state_id, hold_id, hold_status) FROM stdin;
\.


--
-- Data for Name: session_states; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.session_states (state_id, state_name) FROM stdin;
1	Early registration
2	Late registration
3	Midterm grading start
4	Midterm grading end
5	Final exam grading start
6	Final exam grading end
\.


--
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.settings (jwt_expiry, credit_price) FROM stdin;
60	95000
\.


--
-- Data for Name: student_enrollment; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.student_enrollment (section_id, student_id, grade, student_enrollment_id) FROM stdin;
5	A00021204	B	193
6	A00021204	B	194
9	A00021204	B	195
10	A00021204	B	196
18	A00021204	B	197
6	A00021247	B	198
19	A00021247	B	199
9	A00021247	B	200
19	A00021524	B	203
4	A00021524	B	205
5	A00021524	B	206
12	A00021524	B	207
18	A00021759	B	208
9	A00021759	B	209
7	A00021759	B	210
20	A00021759	B	212
13	A00021606	B	213
18	A00021606	B	214
4	A00021606	B	215
10	A00021606	B	216
15	A00021606	B	217
8	A00021186	B	218
5	A00021186	B	219
11	A00021186	B	220
13	A00021186	B	221
18	A00021186	B	222
3	A00021110	B	223
8	A00021110	B	224
12	A00021110	B	225
2	A00021110	B	227
15	A00021874	B	228
21	A00021874	B	229
19	A00021874	B	230
16	A00021874	B	231
8	A00021874	B	232
69	A00021204	A-	233
75	A00021204	C+	234
77	A00021204	A	235
54	A00021204	C	236
64	A00021204	B+	237
81	A00021204	F	238
56	A00021204	C+	239
72	A00021204	C+	240
62	A00021204	A-	241
63	A00021204	C+	242
55	A00021204	D	243
73	A00021204	B	244
67	A00021204	B+	245
68	A00021204	D	246
76	A00021247	A-	247
60	A00021247	A-	248
73	A00021247	D	249
53	A00021247	B-	250
69	A00021247	B-	251
74	A00021247	A-	252
71	A00021247	F	253
55	A00021247	B-	254
57	A00021247	B	255
72	A00021247	F	256
59	A00021247	C	257
70	A00021247	B-	258
64	A00021247	D	259
75	A00021247	C	260
76	A00021524	C	261
67	A00021524	A-	262
81	A00021524	B	263
60	A00021524	A	264
52	A00021524	B	265
74	A00021524	F	266
64	A00021524	A	267
61	A00021524	C	268
58	A00021524	C+	269
72	A00021524	C+	270
57	A00021524	A	271
71	A00021524	B-	272
77	A00021524	C+	273
63	A00021524	D	274
73	A00021524	D	275
53	A00021524	B	276
70	A00021759	C	277
56	A00021759	C+	278
64	A00021759	B+	279
61	A00021759	A-	280
59	A00021759	D	281
52	A00021759	C+	282
71	A00021759	A	283
67	A00021759	D	284
66	A00021759	B+	285
72	A00021759	B+	286
77	A00021759	D	287
62	A00021759	B	288
63	A00021759	B-	289
68	A00021759	A	290
74	A00021759	B	291
61	A00021606	A-	292
72	A00021606	D	293
76	A00021606	B	294
70	A00021606	B	295
69	A00021606	C	296
52	A00021606	B+	297
63	A00021606	B	298
67	A00021606	F	299
55	A00021606	C+	300
53	A00021606	F	301
66	A00021606	B-	302
79	A00021606	C	303
71	A00021606	B+	304
77	A00021606	D	305
58	A00021606	A	306
67	A00021186	B+	307
52	A00021186	A-	308
53	A00021186	C	309
64	A00021186	C+	310
71	A00021186	A-	311
56	A00021186	B	312
75	A00021186	C	313
72	A00021186	B	314
80	A00021186	B-	315
63	A00021186	F	316
74	A00021186	A	317
58	A00021186	B	318
66	A00021186	C	319
71	A00021110	D	320
74	A00021110	B-	321
53	A00021110	A	322
80	A00021110	C+	323
55	A00021110	A	324
60	A00021110	B+	325
61	A00021110	D	326
78	A00021110	C	327
62	A00021110	B+	328
75	A00021110	C+	329
81	A00021110	A	330
72	A00021110	C	331
79	A00021110	A-	332
56	A00021110	D	333
58	A00021110	B-	334
78	A00021874	D	335
59	A00021874	D	336
60	A00021874	C	337
80	A00021874	A	338
65	A00021874	A-	339
55	A00021874	B	340
69	A00021874	D	341
62	A00021874	D	342
70	A00021874	B+	343
68	A00021874	A	344
56	A00021874	A-	345
77	A00021874	D	346
63	A00021874	D	347
74	A00021976	A	348
67	A00021976	C	349
80	A00021976	A	350
71	A00021976	C+	351
79	A00021976	F	352
56	A00021976	C	353
63	A00021976	B-	354
73	A00021976	A-	355
76	A00021976	B-	356
58	A00021976	D	357
72	A00021976	B+	358
77	A00021976	C+	359
78	A00021976	C+	360
59	A00021976	B-	361
69	A00021976	B-	362
70	A00021298	F	363
81	A00021298	C	364
53	A00021298	B+	365
57	A00021298	D	366
74	A00021298	A-	367
60	A00021298	B	368
61	A00021298	B	369
56	A00021298	B	370
72	A00021298	B-	371
62	A00021298	B+	372
66	A00021298	C+	373
64	A00021298	F	374
80	A00021298	C	375
82	A00021110	\N	429
85	A00021204	\N	1332
86	A00021110	\N	1339
83	A00021204	\N	1340
\.


--
-- Data for Name: student_year_per_program; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.student_year_per_program (program_id, year_id, from_credits, to_credits) FROM stdin;
1	1	0	30
1	2	30	60
1	3	60	90
1	4	90	999
\.


--
-- Data for Name: student_years; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.student_years (year_id, year_name) FROM stdin;
1	First Year Student
2	Second Year Student
3	Third Year Student
4	Fourth Year Student
\.


--
-- Data for Name: students; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.students (student_id, status, date_of_birth, date_of_admission, level, major, minor, concentration, school, address, password, email, phone_number, first_name, middle_name, last_name, term_of_admission, program_id, gender, state_of_origin, lga) FROM stdin;
A00021204	Active	2001-06-17	2022-03-20	Undergraduate	Computer Science	\N	\N	1	3 Walton Point	valid	nflott0@state.tx.us	08099633884	Jeanne	Nikolaos	Flott	1	1	Male	Adamawa	Yola
A00021247	Active	2001-08-06	2020-02-19	Undergraduate	Computer Science	\N	\N	1	24 Westend Parkway	valid	lrust1@nsw.gov.au	08019885560	Kaila	Leesa	Rust	1	1	Male	Adamawa	Yola
A00021524	Active	2001-10-31	2020-02-02	Undergraduate	Computer Science	\N	\N	1	62565 Daystar Trail	valid	gsaffill2@sogou.com	08085761933	Giuditta	\N	Saffill	1	1	Male	Adamawa	Yola
A00021759	Active	2003-03-09	2022-05-27	Undergraduate	Computer Science	\N	\N	1	2 Pankratz Court	valid	ssilman3@home.pl	08070380892	Cesar	\N	Silman	1	1	Male	Adamawa	Yola
A00021606	Active	2000-09-16	2021-02-15	Undergraduate	Computer Science	\N	\N	1	9 Memorial Pass	valid	aputtrell4@google.com.br	08009872322	Avram	\N	Puttrell	1	1	Male	Adamawa	Yola
A00021186	Active	2000-12-09	2021-04-08	Undergraduate	Computer Science	\N	\N	1	115 Veith Avenue	valid	crantoull5@behance.net	08016517458	Frances	Clementius	Rantoull	1	1	Male	Adamawa	Yola
A00021110	Active	2003-07-20	2020-11-27	Undergraduate	Computer Science	\N	\N	1	49347 Summit Pass	valid	tgoschalk6@toplist.cz	08081129211	Afton	\N	Goschalk	1	1	Male	Adamawa	Yola
A00021874	Active	2003-05-26	2021-02-01	Undergraduate	Computer Science	\N	\N	1	96 Becker Junction	valid	rbims7@who.int	08001924236	Eldredge	Rodrigo	Bims	1	1	Male	Adamawa	Yola
A00021976	Active	2003-09-01	2021-10-21	Undergraduate	Computer Science	\N	\N	1	6092 Sachs Park	valid	wboles8@dailymotion.com	08016124910	Rosemarie	\N	Boles	1	1	Male	Adamawa	Yola
A00021298	Active	2002-10-30	2022-09-01	Undergraduate	Computer Science	\N	\N	1	204 Porter Avenue	valid	kdumbarton9@elegantthemes.com	08069493344	Forester	\N	Dumbarton	1	1	Male	Adamawa	Yola
\.


--
-- Data for Name: t_amount; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.t_amount ("?column?") FROM stdin;
285000
\.


--
-- Data for Name: test; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.test (name, number) FROM stdin;
najeeb	1
najeeb	123
udo	4
\.


--
-- Data for Name: transaction; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.transaction (student_id, transaction_type, description, date, amount, transaction_id, session_id) FROM stdin;
A00021204	credit	Spring 2023 fees	2022-11-01	1000000	2	5
A00021204	debit	System: Course Debit	2022-11-01	285000	5	\N
A00021204	credit	System: Course Credit	2022-11-01	285000	6	\N
A00021204	debit	System: Course Debit	2022-11-02	285000	14	\N
A00021204	credit	System: Course Credit	2022-11-02	28500	19	\N
A00021204	credit	System: Course Credit	2022-11-02	285000	20	\N
A00021204	debit	System: Course Debit	2022-11-02	285000	21	5
A00021204	credit	System: Course Credit	2022-11-02	285000	22	5
A00021204	credit	System: Course Credit	2022-11-02	285000	23	5
A00021204	debit	System: Course Debit	2022-11-02	285000	24	5
A00021204	debit	System: Course Debit	2022-11-02	285000	25	5
A00021204	credit	System: Course Credit	2022-11-02	285000	26	5
A00021204	debit	System: Course Debit	2022-11-02	285000	27	5
A00021204	credit	System: Course Credit	2022-11-02	285000	28	5
A00021204	credit	System: Course Credit	2022-11-02	285000	29	5
A00021204	debit	System: Course Debit	2022-11-02	285000	30	5
A00021204	debit	System: Course Debit	2022-11-02	285000	31	5
A00021204	credit	System: Course Credit	2022-11-02	285000	32	5
A00021204	debit	System: Course Debit	2022-11-02	285000	33	5
A00021204	credit	System: Course Credit	2022-11-02	285000	34	5
A00021204	debit	System: Course Debit	2022-11-02	285000	35	5
A00021204	credit	System: Course Credit	2022-11-02	285000	36	5
A00021204	debit	System: Course Debit	2022-11-02	285000	37	5
A00021204	credit	System: Course Credit	2022-11-02	285000	38	5
A00021110	credit	System: Course Credit	2022-11-02	285000	39	5
A00021110	credit	System: Course Credit	2022-11-02	285000	40	5
A00021110	debit	System: Course Debit	2022-11-02	285000	41	5
A00021110	debit	System: Course Debit	2022-11-02	285000	42	5
A00021110	credit	System: Course Credit	2022-11-02	285000	43	5
A00021110	debit	System: Course Debit	2022-11-02	285000	44	5
A00021110	credit	System: Course Credit	2022-11-02	285000	45	5
A00021110	debit	System: Course Debit	2022-11-02	285000	46	5
A00021110	credit	System: Course Credit	2022-11-02	285000	47	5
A00021110	debit	System: Course Debit	2022-11-02	285000	48	5
A00021110	credit	System: Course Credit	2022-11-02	285000	49	5
A00021110	debit	System: Course Debit	2022-11-02	285000	50	5
A00021110	credit	System: Course Credit	2022-11-02	285000	51	5
A00021110	debit	System: Course Debit	2022-11-02	285000	52	5
A00021110	credit	System: Course Credit	2022-11-02	285000	53	5
A00021204	debit	System: Course Debit	2022-11-02	285000	54	5
A00021204	debit	System: Course Debit	2022-11-02	285000	55	5
A00021204	credit	System: Course Credit	2022-11-02	285000	56	5
A00021204	credit	System: Course Credit	2022-11-02	285000	57	5
A00021204	credit	System: Course Credit	2022-11-03	285000	58	5
A00021204	debit	System: Course Debit	2022-11-03	285000	59	5
A00021204	credit	System: Course Credit	2022-11-03	285000	60	5
A00021204	debit	System: Course Debit	2022-11-03	285000	61	5
A00021110	debit	System: Course Debit	2022-11-03	285000	62	5
A00021110	credit	System: Course Credit	2022-11-03	285000	63	5
A00021110	debit	System: Course Debit	2022-11-03	285000	64	5
A00021110	credit	System: Course Credit	2022-11-03	285000	65	5
A00021110	debit	System: Course Debit	2022-11-03	285000	66	5
A00021110	credit	System: Course Credit	2022-11-03	285000	67	5
A00021110	debit	System: Course Debit	2022-11-03	285000	68	5
A00021204	credit	System: Course Credit	2022-11-04	285000	69	5
A00021204	debit	System: Course Debit	2022-11-04	285000	70	5
\.


--
-- Name: class_dates_abbrev_class_abbrev_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.class_dates_abbrev_class_abbrev_id_seq', 4, true);


--
-- Name: class_dates_class_dates_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.class_dates_class_dates_id_seq', 8, true);


--
-- Name: class_times_class_time_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.class_times_class_time_id_seq', 6, true);


--
-- Name: days_day_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.days_day_id_seq', 7, true);


--
-- Name: grade_assignments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.grade_assignments_id_seq', 14, true);


--
-- Name: hold_exceptions_table_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.hold_exceptions_table_id_seq', 4, true);


--
-- Name: individual_holds_hold_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.individual_holds_hold_id_seq', 1, false);


--
-- Name: max_courses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.max_courses_id_seq', 2, true);


--
-- Name: overloads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.overloads_id_seq', 5, true);


--
-- Name: overrides_override_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.overrides_override_id_seq', 5, true);


--
-- Name: programs_program_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.programs_program_id_seq', 1, true);


--
-- Name: role_holds_hold_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.role_holds_hold_id_seq', 3, true);


--
-- Name: schools_school_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.schools_school_id_seq', 1, true);


--
-- Name: section_times_section_time_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.section_times_section_time_id_seq', 8, true);


--
-- Name: sections_section_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.sections_section_id_seq', 86, true);


--
-- Name: session_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.session_session_id_seq', 5, true);


--
-- Name: session_states_state_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.session_states_state_id_seq', 6, true);


--
-- Name: student_enrollment_student_enrollment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.student_enrollment_student_enrollment_id_seq', 1340, true);


--
-- Name: transaction_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: doadmin
--

SELECT pg_catalog.setval('public.transaction_transaction_id_seq', 70, true);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: basic_auth; Owner: doadmin
--

ALTER TABLE ONLY basic_auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: students AUN_ID; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT "AUN_ID" PRIMARY KEY (student_id);


--
-- Name: courses CRN; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT "CRN" PRIMARY KEY (course_id);


--
-- Name: class_dates_abbrev class_dates_abbrev_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_dates_abbrev
    ADD CONSTRAINT class_dates_abbrev_pkey PRIMARY KEY (class_abbrev_id);


--
-- Name: class_dates class_dates_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_dates
    ADD CONSTRAINT class_dates_pkey PRIMARY KEY (class_dates_id);


--
-- Name: class_times class_times_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_times
    ADD CONSTRAINT class_times_pkey PRIMARY KEY (class_time_id);


--
-- Name: days days_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.days
    ADD CONSTRAINT days_pkey PRIMARY KEY (day_id);


--
-- Name: hold_exceptions hold_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.hold_exceptions
    ADD CONSTRAINT hold_exceptions_pkey PRIMARY KEY (table_id);


--
-- Name: faculty id; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.faculty
    ADD CONSTRAINT id PRIMARY KEY (faculty_id);


--
-- Name: faculty_assignment identificationfacenroll; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.faculty_assignment
    ADD CONSTRAINT identificationfacenroll PRIMARY KEY (fac_id, sid);


--
-- Name: individual_hold_members individual_hold_members_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.individual_hold_members
    ADD CONSTRAINT individual_hold_members_pkey PRIMARY KEY (hold_id, member_id);


--
-- Name: individual_holds individual_holds_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.individual_holds
    ADD CONSTRAINT individual_holds_pkey PRIMARY KEY (hold_id);


--
-- Name: location location_key; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_key PRIMARY KEY (location_id);


--
-- Name: max_courses max_courses_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.max_courses
    ADD CONSTRAINT max_courses_pkey PRIMARY KEY (id);


--
-- Name: overloads overloads_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overloads
    ADD CONSTRAINT overloads_pkey PRIMARY KEY (overload_id);


--
-- Name: overrides overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overrides
    ADD CONSTRAINT overrides_pkey PRIMARY KEY (override_id);


--
-- Name: prerequisites prerequisites_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.prerequisites
    ADD CONSTRAINT prerequisites_pkey PRIMARY KEY (course_id, pre_req_course_id);


--
-- Name: programs programs_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.programs
    ADD CONSTRAINT programs_pkey PRIMARY KEY (program_id);


--
-- Name: role_holds role_holds_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.role_holds
    ADD CONSTRAINT role_holds_pkey PRIMARY KEY (hold_id);


--
-- Name: schools schools_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_pkey PRIMARY KEY (school_id);


--
-- Name: section_times section_times_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.section_times
    ADD CONSTRAINT section_times_pkey PRIMARY KEY (section_time_id);


--
-- Name: sections sections_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_pkey PRIMARY KEY (section_id);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (session_id);


--
-- Name: session_state_holds session_state_holds_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session_state_holds
    ADD CONSTRAINT session_state_holds_pkey PRIMARY KEY (session_state_id, hold_id);


--
-- Name: session_states session_states_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session_states
    ADD CONSTRAINT session_states_pkey PRIMARY KEY (state_id);


--
-- Name: student_enrollment student_enrollment_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_pkey PRIMARY KEY (section_id, student_id);


--
-- Name: student_year_per_program student_year_per_program_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_year_per_program
    ADD CONSTRAINT student_year_per_program_pkey PRIMARY KEY (program_id, year_id);


--
-- Name: student_years student_years_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_years
    ADD CONSTRAINT student_years_pkey PRIMARY KEY (year_id);


--
-- Name: student_years student_years_year_name_key; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_years
    ADD CONSTRAINT student_years_year_name_key UNIQUE (year_name);


--
-- Name: transaction transaction_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_pkey PRIMARY KEY (transaction_id);


--
-- Name: users encrypt_pass; Type: TRIGGER; Schema: basic_auth; Owner: doadmin
--

CREATE TRIGGER encrypt_pass BEFORE INSERT OR UPDATE ON basic_auth.users FOR EACH ROW EXECUTE FUNCTION basic_auth.encrypt_pass();


--
-- Name: users ensure_user_role_exists; Type: TRIGGER; Schema: basic_auth; Owner: doadmin
--

CREATE CONSTRAINT TRIGGER ensure_user_role_exists AFTER INSERT OR UPDATE ON basic_auth.users NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION basic_auth.check_role_exists();


--
-- Name: students create_user_student; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER create_user_student BEFORE INSERT ON public.students FOR EACH ROW EXECUTE FUNCTION public.create_user_student();


--
-- Name: student_enrollment grade_exists; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER grade_exists BEFORE INSERT OR UPDATE ON public.student_enrollment FOR EACH ROW EXECUTE FUNCTION public.grade_exists();


--
-- Name: student_enrollment student_course_chage_trigger; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER student_course_chage_trigger AFTER INSERT OR DELETE ON public.student_enrollment FOR EACH ROW EXECUTE FUNCTION public.apply_course_charges();


--
-- Name: registration student_registration_trigger; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER student_registration_trigger INSTEAD OF INSERT OR DELETE ON public.registration FOR EACH ROW EXECUTE FUNCTION public.student_course_registration();


--
-- Name: class_dates class_dates_class_abbrev_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_dates
    ADD CONSTRAINT class_dates_class_abbrev_id_fkey FOREIGN KEY (class_abbrev_id) REFERENCES public.class_dates_abbrev(class_abbrev_id);


--
-- Name: class_dates class_dates_day_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.class_dates
    ADD CONSTRAINT class_dates_day_id_fkey FOREIGN KEY (day_id) REFERENCES public.days(day_id);


--
-- Name: faculty_assignment faculty; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.faculty_assignment
    ADD CONSTRAINT faculty FOREIGN KEY (fac_id) REFERENCES public.faculty(faculty_id);


--
-- Name: individual_hold_members individual_hold_members_hold_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.individual_hold_members
    ADD CONSTRAINT individual_hold_members_hold_id_fkey FOREIGN KEY (hold_id) REFERENCES public.individual_holds(hold_id);


--
-- Name: individual_hold_members individual_hold_members_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.individual_hold_members
    ADD CONSTRAINT individual_hold_members_member_id_fkey FOREIGN KEY (member_id) REFERENCES basic_auth.users(id);


--
-- Name: max_courses max_courses_school_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.max_courses
    ADD CONSTRAINT max_courses_school_fkey FOREIGN KEY (school) REFERENCES public.schools(school_id);


--
-- Name: overloads overloads_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overloads
    ADD CONSTRAINT overloads_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.session(session_id);


--
-- Name: overloads overloads_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overloads
    ADD CONSTRAINT overloads_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: overrides overrides_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overrides
    ADD CONSTRAINT overrides_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: overrides overrides_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.overrides
    ADD CONSTRAINT overrides_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: prerequisites prerequisites_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.prerequisites
    ADD CONSTRAINT prerequisites_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: prerequisites prerequisites_pre_req_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.prerequisites
    ADD CONSTRAINT prerequisites_pre_req_course_id_fkey FOREIGN KEY (pre_req_course_id) REFERENCES public.courses(course_id);


--
-- Name: students program_id_student_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT program_id_student_fk FOREIGN KEY (program_id) REFERENCES public.programs(program_id);


--
-- Name: schools schools_dean_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_dean_fkey FOREIGN KEY (dean) REFERENCES public.faculty(faculty_id);


--
-- Name: faculty_assignment sec_id; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.faculty_assignment
    ADD CONSTRAINT sec_id FOREIGN KEY (sid) REFERENCES public.sections(section_id);


--
-- Name: sections section_time_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT section_time_id_fk FOREIGN KEY (section_time_id) REFERENCES public.section_times(section_time_id);


--
-- Name: section_times section_times_class_dates_abbrev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.section_times
    ADD CONSTRAINT section_times_class_dates_abbrev_fkey FOREIGN KEY (class_dates_abbrev) REFERENCES public.class_dates_abbrev(class_abbrev_id);


--
-- Name: section_times section_times_class_time_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.section_times
    ADD CONSTRAINT section_times_class_time_id_fkey FOREIGN KEY (class_time_id) REFERENCES public.class_times(class_time_id);


--
-- Name: sections sections_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: sections session_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT session_id_fk FOREIGN KEY (session_id) REFERENCES public.session(session_id);


--
-- Name: session_state_holds session_state_holds_hold_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session_state_holds
    ADD CONSTRAINT session_state_holds_hold_id_fkey FOREIGN KEY (hold_id) REFERENCES public.role_holds(hold_id);


--
-- Name: session_state_holds session_state_holds_session_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session_state_holds
    ADD CONSTRAINT session_state_holds_session_state_id_fkey FOREIGN KEY (session_state_id) REFERENCES public.session_states(state_id);


--
-- Name: session session_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.session_states(state_id);


--
-- Name: transaction session_transaction_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT session_transaction_fk FOREIGN KEY (session_id) REFERENCES public.session(session_id);


--
-- Name: student_enrollment student_enrollment_section_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_section_id_fk FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: student_enrollment student_enrollment_student_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_student_id_fk FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: transaction student_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT student_id_fk FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: students student_school_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT student_school_fk FOREIGN KEY (school) REFERENCES public.schools(school_id);


--
-- Name: students student_session_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT student_session_fk FOREIGN KEY (term_of_admission) REFERENCES public.session(session_id);


--
-- Name: student_year_per_program student_year_per_program_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_year_per_program
    ADD CONSTRAINT student_year_per_program_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.programs(program_id);


--
-- Name: student_year_per_program student_year_per_program_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.student_year_per_program
    ADD CONSTRAINT student_year_per_program_year_id_fkey FOREIGN KEY (year_id) REFERENCES public.student_years(year_id);


--
-- Name: faculty; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.faculty ENABLE ROW LEVEL SECURITY;

--
-- Name: student_enrollment faculty_enrollment_view; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY faculty_enrollment_view ON public.student_enrollment USING ((COALESCE(( SELECT faculty_assignment.sid
   FROM public.faculty_assignment
  WHERE (((faculty_assignment.fac_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)) AND (faculty_assignment.sid = student_enrollment.section_id))), 0) = section_id));


--
-- Name: faculty faculty_select; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY faculty_select ON public.faculty USING (((faculty_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)));


--
-- Name: individual_hold_members; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.individual_hold_members ENABLE ROW LEVEL SECURITY;

--
-- Name: overloads; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.overloads ENABLE ROW LEVEL SECURITY;

--
-- Name: overrides; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.overrides ENABLE ROW LEVEL SECURITY;

--
-- Name: student_enrollment registrar_all_permissions_enrollment; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY registrar_all_permissions_enrollment ON public.student_enrollment TO registrar USING (true) WITH CHECK (true);


--
-- Name: students student_data; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_data ON public.students FOR SELECT USING ((((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text) = (student_id)::text));


--
-- Name: student_enrollment; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.student_enrollment ENABLE ROW LEVEL SECURITY;

--
-- Name: faculty student_faculty_view; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_faculty_view ON public.faculty TO student USING (true);


--
-- Name: overloads student_overload_read; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_overload_read ON public.overloads FOR SELECT TO student USING (((student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)));


--
-- Name: overloads student_overload_write; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_overload_write ON public.overloads FOR INSERT TO student WITH CHECK (((student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)));


--
-- Name: overrides student_override_read; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_override_read ON public.overrides FOR SELECT TO student USING (((student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)));


--
-- Name: overrides student_override_write; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_override_write ON public.overrides FOR INSERT TO student WITH CHECK (((student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)));


--
-- Name: transaction student_transaction_read; Type: POLICY; Schema: public; Owner: doadmin
--

CREATE POLICY student_transaction_read ON public.transaction FOR SELECT TO student USING (((student_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'id'::text)));


--
-- Name: students; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

--
-- Name: transaction; Type: ROW SECURITY; Schema: public; Owner: doadmin
--

ALTER TABLE public.transaction ENABLE ROW LEVEL SECURITY;

--
-- Name: FUNCTION login(id text, pass text); Type: ACL; Schema: basic_auth; Owner: doadmin
--

REVOKE ALL ON FUNCTION basic_auth.login(id text, pass text) FROM PUBLIC;


--
-- Name: FUNCTION adduploader(integer, text, text); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.adduploader(integer, text, text) FROM PUBLIC;


--
-- Name: FUNCTION apply_course_charges(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.apply_course_charges() FROM PUBLIC;


--
-- Name: FUNCTION are_prerequisites_satisfied(student_id character varying, course_id integer); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.are_prerequisites_satisfied(student_id character varying, course_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.are_prerequisites_satisfied(student_id character varying, course_id integer) TO student;


--
-- Name: FUNCTION conflicts_with_registration(section_id integer, student_id character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.conflicts_with_registration(section_id integer, student_id character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION public.conflicts_with_registration(section_id integer, student_id character varying) TO student;


--
-- Name: FUNCTION create_user_student(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.create_user_student() FROM PUBLIC;


--
-- Name: FUNCTION get_account_balance(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_account_balance() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_account_balance() TO student;


--
-- Name: FUNCTION get_age(birthday date); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_age(birthday date) FROM PUBLIC;


--
-- Name: FUNCTION get_attempted_hours(input_student_id character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_attempted_hours(input_student_id character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_attempted_hours(input_student_id character varying) TO student;


--
-- Name: FUNCTION get_cgpa(student_id text); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_cgpa(student_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_cgpa(student_id text) TO student;


--
-- Name: FUNCTION get_earned_hours(input_student_id character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_earned_hours(input_student_id character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_earned_hours(input_student_id character varying) TO student;


--
-- Name: FUNCTION get_enrollment_number(section_id integer); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_enrollment_number(section_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_enrollment_number(section_id integer) TO student;


--
-- Name: FUNCTION get_id(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_id() TO anon;
GRANT ALL ON FUNCTION public.get_id() TO student;


--
-- Name: FUNCTION get_max_courses(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_max_courses() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_max_courses() TO student;


--
-- Name: FUNCTION get_role(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_role() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_role() TO student;
GRANT ALL ON FUNCTION public.get_role() TO faculty;
GRANT ALL ON FUNCTION public.get_role() TO registrar;


--
-- Name: FUNCTION get_student_year(input_student_id character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_student_year(input_student_id character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_student_year(input_student_id character varying) TO student;


--
-- Name: FUNCTION get_total_quality_points(student_id text); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.get_total_quality_points(student_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_total_quality_points(student_id text) TO student;


--
-- Name: FUNCTION grade_exists(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.grade_exists() FROM PUBLIC;


--
-- Name: FUNCTION is_class_full(section_id integer); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.is_class_full(section_id integer) FROM PUBLIC;


--
-- Name: FUNCTION is_course_limit_reached(student_id character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.is_course_limit_reached(student_id character varying) FROM PUBLIC;


--
-- Name: FUNCTION is_passing_grade(grade character varying, course integer); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.is_passing_grade(grade character varying, course integer) FROM PUBLIC;


--
-- Name: FUNCTION is_passing_grade(grade character varying, course character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.is_passing_grade(grade character varying, course character varying) FROM PUBLIC;


--
-- Name: FUNCTION is_time_conflicting(t1 integer, t2 integer); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.is_time_conflicting(t1 integer, t2 integer) FROM PUBLIC;


--
-- Name: FUNCTION login(id text, pass text); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.login(id text, pass text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.login(id text, pass text) TO anon;


--
-- Name: FUNCTION on_hold(id character varying, restricted_table character varying, operation character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.on_hold(id character varying, restricted_table character varying, operation character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION public.on_hold(id character varying, restricted_table character varying, operation character varying) TO student;


--
-- Name: FUNCTION quality_points(c_id integer, grade_gotten character varying); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.quality_points(c_id integer, grade_gotten character varying) FROM PUBLIC;


--
-- Name: FUNCTION student_course_registration(); Type: ACL; Schema: public; Owner: doadmin
--

REVOKE ALL ON FUNCTION public.student_course_registration() FROM PUBLIC;


--
-- Name: TABLE class_dates_abbrev; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.class_dates_abbrev TO student;
GRANT SELECT ON TABLE public.class_dates_abbrev TO faculty;


--
-- Name: TABLE class_times; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.class_times TO student;
GRANT SELECT ON TABLE public.class_times TO faculty;


--
-- Name: TABLE courses; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.courses TO student;
GRANT SELECT ON TABLE public.courses TO faculty;


--
-- Name: TABLE faculty; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.faculty TO faculty;


--
-- Name: COLUMN faculty.faculty_id; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT(faculty_id) ON TABLE public.faculty TO student;


--
-- Name: COLUMN faculty.department; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT(department) ON TABLE public.faculty TO student;


--
-- Name: COLUMN faculty.email; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT(email) ON TABLE public.faculty TO student;


--
-- Name: COLUMN faculty.f_name; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT(f_name) ON TABLE public.faculty TO student;


--
-- Name: COLUMN faculty.m_name; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT(m_name) ON TABLE public.faculty TO student;


--
-- Name: COLUMN faculty.l_name; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT(l_name) ON TABLE public.faculty TO student;


--
-- Name: TABLE faculty_assignment; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.faculty_assignment TO student;
GRANT SELECT ON TABLE public.faculty_assignment TO faculty;


--
-- Name: TABLE section_times; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.section_times TO student;
GRANT SELECT ON TABLE public.section_times TO faculty;


--
-- Name: TABLE sections; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.sections TO student;
GRANT SELECT ON TABLE public.sections TO faculty;


--
-- Name: TABLE session; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.session TO student;
GRANT SELECT ON TABLE public.session TO faculty;


--
-- Name: TABLE student_enrollment; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.student_enrollment TO faculty;


--
-- Name: TABLE all_sections; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.all_sections TO student;


--
-- Name: TABLE concise_schedule; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.concise_schedule TO student;


--
-- Name: TABLE students; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.students TO student;


--
-- Name: TABLE enrollments; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.enrollments TO student;


--
-- Name: TABLE faculty_schedule; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.faculty_schedule TO faculty;


--
-- Name: TABLE hold_exceptions; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.hold_exceptions TO student;


--
-- Name: TABLE individual_hold_members; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.individual_hold_members TO student;


--
-- Name: TABLE individual_holds; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.individual_holds TO student;


--
-- Name: TABLE max_courses; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.max_courses TO student;


--
-- Name: TABLE overloads; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT,INSERT ON TABLE public.overloads TO student;


--
-- Name: SEQUENCE overloads_id_seq; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.overloads_id_seq TO student;


--
-- Name: TABLE overrides; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT,INSERT ON TABLE public.overrides TO student;


--
-- Name: SEQUENCE overrides_override_id_seq; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.overrides_override_id_seq TO student;


--
-- Name: TABLE registration; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT,INSERT,DELETE ON TABLE public.registration TO student;


--
-- Name: TABLE role_holds; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.role_holds TO student;


--
-- Name: TABLE schools; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.schools TO student;


--
-- Name: TABLE student_data; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.student_data TO student;


--
-- Name: TABLE student_year_per_program; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.student_year_per_program TO student;


--
-- Name: TABLE students_enrolled; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.students_enrolled TO faculty;


--
-- Name: TABLE test; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.test TO anon;


--
-- Name: TABLE transaction; Type: ACL; Schema: public; Owner: doadmin
--

GRANT SELECT ON TABLE public.transaction TO student;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: -; Owner: doadmin
--

ALTER DEFAULT PRIVILEGES FOR ROLE doadmin REVOKE ALL ON FUNCTIONS  FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

