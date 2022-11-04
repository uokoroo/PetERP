from django.shortcuts import render
from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse

from django.http import HttpResponseRedirect
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
        faculty_data = requests.get(URL+"/faculty",headers={'Authorization':'Bearer ' + token})
        # concise_schedule = requests.get(URL+"/concise_schedule",headers={'Authorization':'Bearer ' + token})

        # if the status_code is 401 it means the token is expired. Redirect the user to logout and create an error message
        if faculty_data.status_code == 401:
            messages.add_message(request,messages.WARNING,"Session expired, please login again")
            return redirect(reverse('faculty:logout'))
        # for the current use case if there is no 401 error then the data is valid
        # this probably will not hold in production but suffices for now
        else:
            # cache the important data about the current use to avoid making repeated api calls
            request.session['faculty_data'] = faculty_data.json()[0]
            # request.session['concise_schedule'] = concise_schedule.json()
        return render(request,"faculty_view/index.html",{
            'faculty_data':faculty_data.json()[0],
            # 'concise_schedule' : concise_schedule.json(),
            })

def logout_user(request):
    # delete the session data and redirect to login. This makes the system forget there's ever been a person logged in
    request.session.flush()
    return redirect(reverse('home:login'))