conc = [
  {
    "student_id": "A00021204",
    "name": "Jeanne Nikolaos Flott",
    "faculty": "Lynne Laurélie Dumke",
    "session": "Fall 2022",
    "session_id": 1,
    "grade": "B",
    "course_code": "CSC 174",
    "title": "JTAPI",
    "credit_hours":3,
  },
  {
    "student_id": "A00021204",
    "name": "Jeanne Nikolaos Flott",
    "faculty": "Raffaello Ruì Jennaway",
    "session": "Fall 2022",
    "session_id": 1,
    "grade": "B",
    "course_code": "CSC 833",
    "title": "CNN Pathfire",
    "credit_hours":3,
  },
  ]

def academic_data(courses):
    grade_assignments = {
        'A':4,
        'A-':3.7,
        'B+':3.3,
        'B':3,
        'B-':2.7,
        'C+':2.3,
        'C':2,
        'D':1,
        'F':0,
        'WP':0,
        'WF':0,
        'I':0,
        }
    gpa = 0
    attempted_hours = 0
    earned_hours = 0
    honors = None
    quality_points = 0
    for course in courses:
        attempted_hours += course['credit_hours'] if course['grade'] not in ['WP','I'] else 0
        if course['grade'] not in ['D','F','WP','WF','I']:
            earned_hours += course['credit_hours']
        quality_points += (grade_assignments[course['grade']] * course['credit_hours'])
    gpa = round(quality_points/attempted_hours,2)
    honors = "Dean's list" if 3.5 <= gpa < 3.8 else "President's list" if gpa > 3.8 else None
    return {
        'gpa':gpa,
        'attempted_hours':attempted_hours,
        'earned_hours':earned_hours,
        'honors':honors,
        'quality_points':quality_points

    }


<<<<<<< Updated upstream
print(order_records_by_session(conc).keys())

=======



print(academic_data(conc))
>>>>>>> Stashed changes
