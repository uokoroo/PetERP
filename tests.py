conc = [
  {
    "student_id": "A00021204",
    "name": "Jeanne Nikolaos Flott",
    "faculty": "Lynne Laurélie Dumke",
    "session": "Fall 2022",
    "session_id": 1,
    "grade": "B",
    "course_code": "CSC 174",
    "title": "JTAPI"
  },
  {
    "student_id": "A00021204",
    "name": "Jeanne Nikolaos Flott",
    "faculty": "Raffaello Ruì Jennaway",
    "session": "Fall 2022",
    "session_id": 1,
    "grade": "B",
    "course_code": "CSC 833",
    "title": "CNN Pathfire"
  },
  ]

def order_records_by_session(enrollments):
    result = {}
    for course in enrollments:
        if course['session'] in result:
            result[course['session']].append(course)
        else:
            result[course['session']] = []
            result[course['session']].append(course)
    return result


print(order_records_by_session(conc).keys())