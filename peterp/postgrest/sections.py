import random

courses = [
 326397368,
 146162475,
 515472798,
 280099426,
 190516729,
 602765844,
   5088799,
 213888523,
 856670399,
 848324025,
]

sessions = [2, 3, 4]

with open ( 'sections.sql', 'w' ) as f:
    for course in courses:
        for session in sessions:
            sql = f"""
            INSERT INTO sections(course_id,session_id,location,capacity,section_time_id)

            VALUES ({course}, {session}, 'Classroom {random.randint(1,20)}',{random.randint(20,50)}, {random.randint(1,8)} );
            """ 
            f.write(sql)