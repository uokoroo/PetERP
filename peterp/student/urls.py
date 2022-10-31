from django.urls import include,path
from . import views

APP_NAME = 'student'

urlpatterns = [
    path("",views.index,name='index'),
    path("profile/", views.profile,name='profile'),
    path("settings/", views.settings,name='settings'),
    path("logout/", views.logout_user,name='logout'),
    path("academics/", views.academics,name='academics'),
    path("registration/", views.registration,name='registration'),
    path("remove/<int:section_id>", views.remove,name='remove'),
    path("add_section/<int:section_id>", views.add_section,name='add_section'),
    path("academic_records/<str:session>", views.semester_records,name='semester_records'),
    path("academic_records/", views.academic_records,name='academic_records'),
    path("courses/", views.courses,name='courses'),
    path("sections/", views.sections,name='sections'),
    path("concise_schedule/", views.concise_schedule,name='concise_schedule'),
    path("cgpa_calculator/", views.cgpa_calculator,name='cgpa_calculator'),
    path("override/", views.override,name='override'),
    path("overload/", views.overload,name='overload'),
    path("account/", views.account,name='account'),
]