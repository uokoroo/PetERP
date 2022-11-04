from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse
# Create your views here.
URL = 'http://aun-erp-api.herokuapp.com'

def index(request):
    # if there is a token in memory it means that the user is logged in
    if request.session.get('token'):
        token = request.session.get('token')
        # get the student_role and return it
        r = requests.post(URL+"/rpc/get_role", headers={'Authorization':'Bearer ' + token})
        if r.status_code - 400 >= 0 and r.status_code - 400 <=99:
            # if the status code is 400 it means it's a bad request so just login again.
            return redirect(reverse('login'))
        else:
            # redirect to the correct app based on the details of the user
            return redirect(f'{r.json()}:index')
    else:
        return redirect(reverse('login'))

 
        

def login_user(request):
    if request.method == 'POST':
        payload = convert(request.POST)
        r = requests.post(URL+"/rpc/login", json=payload)
        # 403 forbidden means the user is not allowed to access this page
        if r.status_code == 403:
            messages.add_message(request, messages.WARNING, r.json().get('message'))
            return redirect(reverse('index'))

        else:
            request.session['token'] = r.json()['token']
            return redirect(reverse('index'))
    return render(request,"login.html")



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