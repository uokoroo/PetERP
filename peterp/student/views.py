from django.shortcuts import render
from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse
# Create your views here.
URL = 'http://aun-erp-api.herokuapp.com'

# Create your views here.
def index(request):
    # if there is a token in memory it means that the user is logged in
    if not request.session.get('token'):
        return redirect('home:login')

    else:
        token = request.session.get('token')
        # make api requests and get important data that will be cached
        student_data = requests.get(URL+"/student_data",headers={'Authorization':'Bearer ' + token})
        concise_schedule = requests.get(URL+"/concise_schedule",headers={'Authorization':'Bearer ' + token})
        # if the status_code is 401 it means the token is expired. Redirect the user to logout and create an error message
        if student_data.status_code == 401 or concise_schedule.status_code == 401:
            messages.add_message(request,messages.WARNING,"Session expired, please login again")
            return redirect(reverse('logout'))
        # for the current use case if there is no 401 error then the data is valid
        # this probably will not hold in production but suffices for now
        else:
            # cache the important data about the current use to avoid making repeated api calls
            request.session['student_data'] = student_data.json()[0]
            request.session['concise_schedule'] = concise_schedule.json()
        return render(request,"student_view/index.html",{
            'student_data':student_data.json()[0],
            'concise_schedule' : concise_schedule.json()
            })



def profile(request):
    # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('login'))
    student_data = request.session.get('student_data')
    concise_schedule = request.session.get('concise_schedule')
    return render(request,'student_view/profile.html',{
        'student_data':student_data,
        'concise_schedule':concise_schedule,

    })



def convert(post_data):
    """
    This function converts the request.POST data gotten into application/json form
    which can be attached to an api request
    """
    json = dict(post_data)
    json.pop("csrfmiddlewaretoken")
    new = {}
    for key in json:
        new[key] = json[key][0]
    return new

    

def redirect_by_code(code):
    """
    This function is meant to handle error codes.
    Any 4** code will be received by this function and the appropriate page will be rendered
    """
    pass


def settings(request):
    return render(request,'student_view/settings.html')

def logout_user(request):
    # delete the session data and redirect to login. This makes the system forget there's ever been a person logged in
    request.session.flush()
    return redirect(reverse('login'))


def academics(request):
        # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('login'))
    student_data = request.session.get('student_data')
    concise_schedule = request.session.get('concise_schedule')
    return render(request,'student_view/academics.html',{
        'student_data':student_data,
        'concise_schedule':concise_schedule,

    })


def registration(request):
    pass


def academic_records(request):
    pass


def cgpa_calculator(request):
    pass


def concise_schedule(request):
    pass


def override(request):
    pass


def overload(request):
    pass


def account(request):
    pass


def courses(request):
    pass


def sections(request):
    pass