from django.urls import include,path
from . import views

app_name = 'faculty'

urlpatterns = [
    path("",views.index,name='index'),
    path("logout/",views.logout_user,name='logout')
]