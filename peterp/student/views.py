from django.shortcuts import render
from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse
from django.core.mail import send_mail

from django.http import HttpResponseRedirect

from .models import StudentMessage
from faculty.models import FacultyMessage


# Create your views here.
URL = 'http://aun-erp-api.herokuapp.com'


def order_records_by_session(enrollments):
    """
    This is supposed to be done with a proper query to the database but it's giving me problems
    and I don't have time to spend reading the documentation.
    For future purposes, the problem is with embedding using views
    """
    result = {}
    for course in enrollments:
        if course['session'] in result:
            result[course['session']].append(course)
        else:
            result[course['session']] = []
            result[course['session']].append(course)
    return result


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
            return redirect(reverse('student:logout'))
        # for the current use case if there is no 401 error then the data is valid
        # this probably will not hold in production but suffices for now
        else:
            # cache the important data about the current use to avoid making repeated api calls
            notifs = StudentMessage.objects.all()
            request.session['student_data'] = student_data.json()[0]
            request.session['concise_schedule'] = concise_schedule.json()
        return render(request,"student_view/index.html",{
            'student_data':student_data.json()[0],
            'concise_schedule' : concise_schedule.json(),
            'messages':notifs
            })



def profile(request):
    token = request.session.get('token')
    # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    concise_schedule = request.session.get('concise_schedule')
    
    balance = requests.get(URL+"/rpc/get_account_balance",headers={'Authorization':'Bearer ' + token}).json()
    return render(request,'student_view/profile.html',{
        'student_data':student_data,
        'concise_schedule':concise_schedule,
        'balance':balance

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

    

def redirect_by_code(request,incoming_request,source_page):
    """
    This function is meant to handle error codes.
    Any 4** code will be received by this function and the appropriate page will be rendered

    I know that this is a bit of an unsavory way of implementing this 
    but it's the fastest and I don't have to use my brain
    """
    code = incoming_request.status_code

    if code - 400 >= 0 and code - 400 <=99:
        messages.add_message(request, messages.WARNING, incoming_request.json()['message'])
        if code == 401:
            return redirect(reverse('home:login'))
        elif code == 403:
            # 403 forbidden means the user is not allowed to access this page
            return render(request,'student_ view/forbidden.html')
        elif code == 404:
            return render(request,'student_ view/notfound404.html')
        else:
            # if the status code is 400 it means it's a bad request so just login again.
            return redirect(reverse(source_page))
    else:
        messages.add_message(request, messages.SUCCESS, "Success")
        return redirect(reverse(source_page))



def settings(request):
    return render(request,'student_view/settings.html')

def logout_user(request):
    # delete the session data and redirect to login. This makes the system forget there's ever been a person logged in
    request.session.flush()
    return redirect(reverse('home:login'))


def academics(request):
        # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    concise_schedule = request.session.get('concise_schedule')
    return render(request,'student_view/academics.html',{
        'student_data':student_data,
        'concise_schedule':concise_schedule,

    })

 
def registration(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        payload = convert(request.POST)

        r = requests.post(URL+"/registration", json=payload,headers={'Authorization':'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            messages.add_message(request, messages.WARNING, r.json()['message'])
            return redirect(reverse('home:login'))
        else:
            messages.add_message(request, messages.SUCCESS, 'Succesfully registered section')
            return redirect(reverse('registration'))
    registration = requests.get(URL+"/registration",headers={'Authorization':'Bearer ' + token})
    sections = requests.get(URL+"/all_sections?order=session_id.desc",headers={'Authorization':'Bearer ' + token})
    if 0 <= registration.status_code - 400 < 100 or 0 <= sections.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, registration.json()['message'])
        return HttpResponseRedirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    on_hold = requests.post(
        URL+"/rpc/user_hold_check",
        headers={'Authorization':'Bearer ' + token, },
        json={"restricted_object":'registration',"operation":"insert"}
        )
    on_hold = on_hold.json()
    return render(request,"student_view/registration.html", {
        'registration':registration.json(),
        'sections': sections.json(),
        "student_data":student_data,
        'on_hold':on_hold
        })


def remove(request,section_id):
    token = request.session.get('token')
    if not token:
        return redirect('home:login')
    delete_req = requests.delete(URL+f"/registration?section_id?section_id=eq.{section_id}",
    headers={
        'Authorization':'Bearer ' + token,
        'Prefer':'return=representation'
    })
    return redirect_by_code(request,delete_req,'student:registration')


def add_section(request,section_id):
    token = request.session.get('token')
    if not token:
        return redirect('home:login')
    add_req = requests.post(
        URL+"/registration",
        headers={
        'Authorization':'Bearer ' + token
        },
        json={"section_id":section_id})
    return redirect_by_code(request,add_req,'student:registration')
    



def academic_records(request):
    """
    ACADEMIC RECORDS HAS TO BE FIXED TO BE A DROPDOWN 
    """
    # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('student_data'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    r = requests.get(URL+"/enrollments",headers={'Authorization':'Bearer ' + token})
    print(r.json())
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        academic_records = r.json()
        academic_records = order_records_by_session(academic_records)
    print(academic_records)
    student_data = request.session.get('student_data')
    request.session['academic_records'] = academic_records
    return render(request,'student_view/academic-record.html',{
        'academic_records':academic_records,
        'student_data':student_data

    })

def semester_records(request,session):
    if not request.session.get('academic_records'):
        return redirect(reverse('home:login'))
    all_data = request.session.get('academic_records')
    session_data = academic_data(all_data[session])
    data = all_data[session]
    student_data = request.session.get('student_data')
    return render(request, 'student_view/academic-records-template.html',{
        'data':data,
        'student_data':student_data,
        'session':session,
        'session_data':session_data,
    })


def cgpa_calculator(request):
    if not request.session.get('student_data'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    print(student_data)
    return render(request,'student_view/cgpa-calculator.html',{
        'student_data':student_data
    }) 


def concise_schedule(request):
        # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    concise_schedule = request.session.get('concise_schedule')
    print(concise_schedule)
    return render(request,'student_view/concise.html',{
        'concise_schedule':concise_schedule,
    })



def override(request):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    override = requests.get(URL+"/overrides?select=*",headers={'Authorization':'Bearer ' + token})
    if 0 <= override.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, override.json()['message'])
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    return render(request,"student_view/override.html", {
        'overrides':override.json(),
        "student_data":student_data,
        })



def new_override(request):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    if request.method == 'POST':
        payload = convert(request.POST)
        r = requests.post(URL+"/overrides", json=payload,headers={'Authorization':'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            print(r.json())
            messages.add_message(request, messages.WARNING, r.json()['message'])
            return redirect(reverse('student:index'))
        else:
            messages.add_message(request, messages.SUCCESS, 'Succesfully created override')
            return redirect(reverse('student:override'))
    override = requests.get(URL+"/overrides?select=*",headers={'Authorization':'Bearer ' + token})
    max_courses = requests.get(URL+"/rpc/get_max_courses",headers={'Authorization':'Bearer ' + token}).json()
    session = requests.get(URL+"/session?select=session_id&status=eq.active&state_id=lt.3",headers={
        'Authorization':'Bearer ' + token,
        'Accept':'application/vnd.pgrst.object+json'
    }).json()
    if 0 <= override.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, override.json()['message'])
        return redirect(reverse('home:login'))

    session = session.get('session_id')
    if not session:
        messages.add_message(request,messages.WARNING,'No semester is open for registration')
        return redirect(reverse('student:index'))
    if 0 <= override.status_code - 400 < 100:
        print(override.json())
        messages.add_message(request, messages.WARNING, override.json()['message'])
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    return render(request,"student_view/add_override.html", {
        'overrides':override.json(),
        "max_courses":max_courses,
        "student_data":student_data,
        "session_id":session
        })



def overload(request):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    if request.method == 'POST':
        payload = convert(request.POST)
        print(payload)
        r = requests.post(URL+"/overloads", json=payload,headers={'Authorization':'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            print(r.json())
            messages.add_message(request, messages.WARNING, r.json()['message'])
            return redirect(reverse('student:index'))
        else:
            messages.add_message(request, messages.SUCCESS, 'Succesfully created overload')
            return redirect(reverse('student:overload'))
    overload = requests.get(URL+"/overloads?select=*,session(semester,year)",headers={'Authorization':'Bearer ' + token})
    max_courses = requests.get(URL+"/rpc/get_max_courses",headers={'Authorization':'Bearer ' + token}).json()
    session = requests.get(URL+"/session?select=session_id&status=eq.active&state_id=lt.3",headers={
        'Authorization':'Bearer ' + token,
        'Accept':'application/vnd.pgrst.object+json'
    }).json()
    session = session.get('session_id')
    if not session:
        messages.add_message(request,messages.WARNING,'No semester is open for registration')
        return render(request,reverse('student:index'))
    if 0 <= overload.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, overload.json()['message'])
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    return render(request,"student_view/overload.html", {
        'overloads':overload.json(),
        "max_courses":max_courses,
        "student_data":student_data,
        "session_id":session
        })


def account(request):
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    student_data = request.session.get('student_data')
    token = request.session['token']
    r = requests.get(URL+"/transaction?select=*,session(semester,year)",headers={'Authorization':'Bearer ' + token})
    r2 = requests.get(URL+"/rpc/get_account_balance",headers={'Authorization':'Bearer ' + token})
    if 0 <= r.status_code - 400 < 100 or 0 <= r2.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('student:account'))
    else:
        transactions = r.json()
        balance = r2.json()
        

    return render(request,'student_view/account.html',{
        'transactions':transactions,
        'balance':balance,
        'student_data':student_data
    })



def courses(request):
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    r = requests.get(URL+"/courses",headers={'Authorization':'Bearer ' + token})
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        courses = r.json()
        

    return render(request,'student_view/courses.html',{
        'courses':courses,
    })


def sections(request):
    if not request.session.get('student_data') or not request.session.get('concise_schedule'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    r = requests.get(URL+"/sections?select=section_id,section_number,location,capacity,session(semester,year),courses(course_code,credit_hours,title),section_times(class_dates_abbrev(abbrev),class_times(str_rep)),faculty_assignment(faculty(f_name,l_name,m_name))",headers={'Authorization':'Bearer ' + token})
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        sections = r.json()
        

    return render(request,'student_view/sections.html',{
        'sections':sections,
    })


def academic_data(courses):
    grade_assignments = {
        'A':4,
        'A-':3.7,
        'B+':3.3,
        'B':3,
        'B-':2.7,
        'C+':2.3,
        'C':2,
        'D':1,
        'F':0,
        'WP':0,
        'WF':0,
        'I':0,
        }
    gpa = 0
    attempted_hours = 0
    earned_hours = 0
    honors = None
    quality_points = 0
    for course in courses:
        print(course)
        print("course['grade']",course['grade'])
        print("course['']",course['credit_hours'])
        attempted_hours += course['credit_hours'] if course['grade'] not in ['WP','I'] else 0
        if course['grade'] not in ['D','F','WP','WF','I']:
            earned_hours += course['credit_hours']

        quality_points += (grade_assignments[course['grade']] * course['credit_hours'])
    gpa = round(quality_points/attempted_hours,2)
    honors = "Dean's list" if 3.5 <= gpa < 3.8 else "President's list" if gpa > 3.8 else None
    return {
        'gpa':gpa,
        'attempted_hours':attempted_hours,
        'earned_hours':earned_hours,
        'honors':honors,
        'quality_points':quality_points

    }
