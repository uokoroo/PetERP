from django.urls import include,path
from . import views

app_name = 'faculty'

urlpatterns = [
    path("",views.index,name='index'),
    path("logout/",views.logout_user,name='logout'),
    path("profile/",views.profile,name='profile'),
    path("dashboard/",views.dashboard,name='dashboard'),
    path("semester_schedule/",views.semester_schedule,name='semester_schedule'),
    path("semester_records/",views.semester_records,name='semester_records'),
    path("course_overview/",views.course_overview,name='course_overview'),
    path("sections/",views.sections,name='sections'),
    path("courses/",views.courses,name='courses'),
    path("overrides/",views.overrides,name='overrides'),
    path("allocated_grades/",views.course_overview,name='allocate_grades'),
    path("grade_history/",views.grade_history,name='grade_history'),
]