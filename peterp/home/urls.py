from django.urls import include,path
from . import views

app_name = 'home'

urlpatterns = [
    path("",views.index,name='index'),
    path("login/", views.login_user,name='login'),
]