from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse
# Create your views here.
URL = 'http://aun-erp-api.herokuapp.com'

def index(request):
    if request.session.get('token'):
        token = request.session.get('token')
        student_data = requests.get(URL+"/student_data",headers={'Authorization':'Bearer ' + token})
        concise_schedule = requests.get(URL+"/concise_schedule",headers={'Authorization':'Bearer ' + token})
        if student_data.status_code == 401 or concise_schedule.status_code == 401:
            messages.add_message(request,messages.WARNING,"Session expired, please login again")
            return redirect(reverse('login'))
        else:
            request.session['student_data'] = student_data.json()[0]
            request.session['concise_schedule'] = concise_schedule.json()
        return render(request,"student_view/index.html",{
            'student_data':student_data.json()[0],
            'concise_schedule' : concise_schedule.json()
            })
    else:
        return render(request,"login.html")

def login(request):
    if request.method == 'POST':
        payload = convert(request.POST)
        r = requests.post(URL+"/rpc/login", json=payload)
        if r.status_code == 403:
            messages.add_message(request, messages.WARNING, r.text['message'])
        else:
            request.session['token'] = r.json()['token']
            return redirect(reverse('index'))

        print(r.status_code)
        print(r.url)
    return render(request,"login.html")

def profile(request):
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('login'))
    student_data = request.session.get('student_data')
    concise_schedule = request.session.get('concise_schedule')
    return render(request,'student_view/profile.html',{
        'student_data':student_data,
        'concise_schedule':concise_schedule,

    })



def convert(post_data):
    json = dict(post_data)
    json.pop("csrfmiddlewaretoken")
    new = {}
    for key in json:
        new[key] = json[key][0]
    return new

    

def redirect_by_code(code):
    pass


def settings(request):
    return render(request,'student_view/settings.html')

def logout_user(request):
    request.session.flush()
    return redirect(reverse('login'))


def academics(request):
    pass


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