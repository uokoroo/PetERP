from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse
# Create your views here.
URL = 'http://aun-erp-api.herokuapp.com'

def index(request):
    print(request.session.get('token'))
    if request.session.get('token'):
        return render(request,"student_view/index.html")
    else:
        return render(request,"login.html")

def login(request):
    if request.method == 'POST':
        payload = convert(request.POST)
        r = requests.post(URL+"/rpc/login", json=payload)
        if r.status_code == 403:
            messages.add_message(request, messages.DANGER, r.text['message'])
        else:
            request.session['token'] = r.json()['token']
            return redirect(reverse('index'))

        print(r.status_code)
        print(r.url)
    return render(request,"login.html")

def profile(request):
    return render(request,'student_view/profile.html')



def convert(post_data):
    json = dict(post_data)
    json.pop("csrfmiddlewaretoken")
    new = {}
    for key in json:
        new[key] = json[key][0]
    return new
    

    