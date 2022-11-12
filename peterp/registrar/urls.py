from django.urls import include,path
from . import views

app_name = 'registrar'

urlpatterns = [
    path("",views.index,name='index'),
    path("logout/",views.logout_user,name='logout'),
    path("profile/",views.profile,name='profile'),
    path("student_info/",views.student_info,name='student_info'),
    path("student_profile/<str:student_id>",views.student_profile,name='student_profile'),
    path("faculty_info/",views.faculty_info,name='faculty_info'),
    path("faculty_profile/<str:faculty_id>",views.faculty_profile,name='faculty_profile'),
    path("section_records/<int:section_id>",views.section_records,name='section_records'),
    path("course_overview/",views.course_overview,name='course_overview'),
    path("sections/",views.sections,name='sections'),
    path("new_section/",views.new_section,name='create_section'),
    path("courses/",views.courses,name='courses'),
    path("new_course/",views.new_course,name='create_course'),
    path("overrides/",views.overrides,name='overrides'),
    path("overloads/",views.overloads,name='overloads'),
    path("allocate_grades/",views.allocate_grades,name='allocate_grades'),
    path("change_grade/<int:enrollment_id>/<str:new_grade>",views.change_grade,name='change_grade'),
    path("grade_history/",views.grade_history,name='grade_history'),
    path("override_action/<int:override_id>/<str:new_state>",views.override_action,name='override_action'),
    path("new_session",views.new_session,name='create-session'),
    path("edit_session",views.edit_session,name='edit-session'),
    path("hold",views.hold,name='hold'),
    path("delete_hold/<int:hold_id>",views.delete_hold,name='delete_hold'),
    path("new_hold",views.new_hold,name='new_hold'),
    path("hold_members/<int:hold_id>",views.hold_members,name='hold_members'),
    path("assign_faculty",views.assign_faculty,name='assign_faculty'),
    path("assign/<int:section_id>/<str:faculty_id>",views.assign,name='assign'),
]