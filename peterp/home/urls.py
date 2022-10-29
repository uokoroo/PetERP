from django.urls import include,path
from . import views

APP_NAME = 'home'

urlpatterns = [
    path("",views.index,name='index'),
    path("login/", views.login,name='login'),
]