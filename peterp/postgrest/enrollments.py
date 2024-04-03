import os
import re
import random

students = ['A00021204',
            'A00021247',
            'A00021524',
            'A00021759',
            'A00021606',
            'A00021186',
            'A00021110',
            'A00021874',
            'A00021976',
            'A00021298']

sections = [
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
]

grades = ['A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'D', 'F']

with open('new_enrollments.sql', 'w') as f:
    for student in students:
        used = []
        for i in range(18):
            ass_section = random.choice(sections)
            if ass_section not in used:
                sql_template = f"""
                    INSERT INTO student_enrollment (section_id, student_id, gradefacul) 
                    VALUES ({ass_section}, '{student}', '{random.choice(grades)}');
                 
                   """
                used.append(ass_section)
                f.write(sql_template)

