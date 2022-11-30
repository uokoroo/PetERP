from django.shortcuts import render
from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse


from collections import OrderedDict

from django.http import HttpResponseRedirect
# Create your views here.
URL = 'http://aun-erp-api.herokuapp.com'

# Create your views here.


def index(request):
    # if there is a token in memory it means that the user is logged in
    if not request.session.get('token'):
        return redirect('home:login')

    token = request.session.get('token')

    def major_info():
        data = {}
        majors = requests.get(URL+"/students?select=major", headers={
                    'Authorization': 'Bearer ' + token
                    })    
        majors = majors.json() if majors.status_code == 200 else []
        for x in majors:
            if x.get('major') not in data:
                data[x['major']] = 1
            else:
                data[x['major']] += 1
        return data
    
    def override_info():
    
        data = {}
        overrides = requests.get(URL+"/overrides?select=section_id,session_id", headers={
                    'Authorization': 'Bearer ' + token
                    })
        overrides = overrides.json() if overrides.status_code == 200 else []
        for x in overrides:
            if x.get('session_id') not in data:
                data[x['session_id']] = 1
            else:
                data[x['session_id']] += 1
        data  = dict(OrderedDict(sorted(data.items())))
        return data

    def overload_info():
        data = {}
        overloads = requests.get(URL+"/overloads?select=session_id", headers={
                    'Authorization': 'Bearer ' + token
                    })
        overloads = overloads.json() if overloads.status_code == 200 else []
        for x in overloads:
            if x.get('session_id') not in data:
                data[x['session_id']] = 1
            else:
                data[x['session_id']] += 1
        data  = dict(OrderedDict(sorted(data.items())))
        return data
    
    major_data = major_info()
    override_data = override_info()
    overload_data = overload_info()
    role = requests.get(URL+"/get_role", headers={
                    'Authorization': 'Bearer ' + token
                    })
    sessions = requests.get(URL+"/session?select=semester,year", headers={
                    'Authorization': 'Bearer ' + token,
                    })

    students = requests.get(URL+"/students?select=student_id", headers={
                    'Authorization': 'Bearer ' + token,
                    }).json()
    faculty = requests.get(URL+"/faculty?select=faculty_id", headers={
                    'Authorization': 'Bearer ' + token,
                    }).json()
    sections = requests.get(URL+"/sections", headers={
                    'Authorization': 'Bearer ' + token,
                    }).json()
    courses = requests.get(URL+"/courses", headers={
                    'Authorization': 'Bearer ' + token,
                    }).json()
    sessions = sessions.json()
    request.session['role'] = role.json()
    current_session =  requests.get(URL+"/session?status=eq.active&state_id=lt.3", headers={
                    'Authorization': 'Bearer ' + token,
                    }).json()
    return render(request, "registrar_view/index.html", {
        'major_data':major_data,
        'overrides':override_data,
        'overloads':overload_data,
        'sessions': sessions,
        'studentLength':len(students),
        'facultyLength':len(faculty),
        'sectionLength':len(sections),
        'courseLength':len(courses),
        'current_session':f"{current_session[0].get('semester')} {current_session[0].get('year')}" 
    })


def student_info(request):
    # if there's no dean_data or profile then the user is not logged in, redirect to login
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session.get('token')

    students = requests.get(URL+"/students",
                     headers={'Authorization': 'Bearer ' + token})
    if 0 <= students.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, students.json()['message'])
        return redirect(reverse('home:login'))
    return render(request,'registrar_view/student_information.html', {
        'students':students.json()
    })

def student_profile(request,student_id):
    # if there's no dean_data or profile then the user is not logged in, redirect to login
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session.get('token')

    student_data = requests.get(URL+f"/students?select=*&student_id=eq.{student_id}",
                     headers={
                        'Authorization': 'Bearer ' + token,
                        'Accept': 'application/vnd.pgrst.object+json'

                        })
    if 0 <= student_data.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, student_data.json()['message'])
        return redirect(reverse('home:login'))
    return render(request,'registrar_view/student_profile.html', {
        'student_data':student_data.json()
    })

def faculty_info(request):
    # if there's no dean_data or profile then the user is not logged in, redirect to login
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session.get('token')

    faculty = requests.get(URL+"/faculty",
                     headers={'Authorization': 'Bearer ' + token})
    if 0 <= faculty.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, faculty.json()['message'])
        return redirect(reverse('home:login'))
    return render(request,'registrar_view/faculty_information.html', {
        'faculty':faculty.json()
    })

def faculty_profile(request,faculty_id):
    # if there's no dean_data or profile then the user is not logged in, redirect to login
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session.get('token')

    faculty_data = requests.get(URL+f"/faculty?select=*&faculty_id=eq.{faculty_id}",
                     headers={
                        'Authorization': 'Bearer ' + token,
                        'Accept': 'application/vnd.pgrst.object+json'

                        })
    if 0 <= faculty_data.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, faculty_data.json()['message'])
        return redirect(reverse('home:login'))
    return render(request,'registrar_view/faculty_profile.html', {
        'faculty_data':faculty_data.json()
    })


def course_overview(request):
    pass


def grade_history(request):
    pass


def allocate_grades(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        # incomplete
        payload = request.POST
        grades = requests.post(URL+"", json=payload,
                               headers={'Authorization': 'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= grades.status_code - 400 < 100:
            messages.add_message(request, messages.WARNING,
                                 grades.json()['message'])
            return redirect(reverse('home:login'))
        else:
            messages.add_message(request, messages.SUCCESS,
                                 'Succesfully changed grade')
            return redirect(reverse('allocate_grades'))
    grades = requests.get(URL+"/student_enrollment?select=*,student:students(first_name,last_name,middle_name),sections!inner(section_id,section_number,course:courses(course_code),session!inner(session_id,semester,year))&sections.session.status=eq.active&sections.session.state_id=gt.4",
                          headers={'Authorization': 'Bearer ' + token})
    if 0 <= grades.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             grades.json()['message'])
        return HttpResponseRedirect(reverse('home:login'))
    dean_data = request.session.get('dean_data')
    return render(request, "dean_view/allocate-grade.html", {
        'grades': grades.json(),
        "faculty_data": dean_data
    })


def profile(request):
    # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('dean_data'):
        return redirect(reverse('home:login'))
    dean_data = request.session.get('dean_data')
    return render(request,'dean_view/profile.html',{
        'faculty_data':dean_data,

    })


def sections(request):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    r = requests.get(URL+"/sections?select=section_id,section_number,location,capacity,session(semester,year),courses(course_code,credit_hours,title),section_times(class_dates_abbrev(abbrev),class_times(str_rep)),faculty_assignment(faculty(f_name,l_name,m_name))",
                     headers={'Authorization': 'Bearer ' + token})
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        sections = r.json()

    return render(request, 'registrar_view/sections.html', {
        'sections': sections,
    })


def courses(request):

    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    r = requests.get(
        URL+"/courses", headers={'Authorization': 'Bearer ' + token})
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        courses = r.json()
    return render(request, 'registrar_view/courses.html', {
        'courses': courses,
    })


def overrides(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        # incomplete
        payload = request.POST
        r = requests.post(URL+"/registration", json=payload,
                          headers={'Authorization': 'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            messages.add_message(
                request, messages.WARNING, r.json()['message'])
            return redirect(reverse('home:login'))
        else:
            messages.add_message(request, messages.SUCCESS,
                                 'Succesfully registered section')
            return redirect(reverse('registration'))
    overrides = requests.get(URL+"/overrides?select=override_id,student_id,section_id,override_type,state,date,section:sections(session(semester,year),capacity,course:courses(course_code,credit_hours,title))",
                             headers={'Authorization': 'Bearer ' + token})
    if 0 <= overrides.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             overrides.json()['message'])
        return HttpResponseRedirect(reverse('home:login'))
    dean_data = request.session.get('dean_data')

    return render(request, "dean_view/override.html", {
        'overrides': overrides.json(),
        "faculty_data": dean_data
    })


def logout_user(request):
    # delete the session data and redirect to login. This makes the system forget there's ever been a person logged in
    request.session.flush()
    return redirect(reverse('home:login'))


def section_records(request, section_id):
    # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('dean_data'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    section_data = requests.get(
        URL +
        f"/sections?select=*,session(semester,year),course:courses(title,course_code),student_enrollment!inner(student:students(first_name,middle_name,last_name,student_id,email))&section_id=eq.{section_id}",
        headers={
            'Authorization': 'Bearer ' + token,
            'Accept': 'application/vnd.pgrst.object+json'
        })
    if 0 <= section_data.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             section_data.json()['message'])
        return redirect(reverse('home:login'))
    else:
        section_data = section_data.json()
    dean_data = request.session.get('dean_data')
    return render(request, 'dean_view/semester_records.html', {
        'section_data': section_data,
        'faculty_data': dean_data

    })



def override_action(request, new_state, override_id):
    token = request.session.get('token')
    if not token:
        return redirect('home:login')
    patch_overrides = requests.patch(
        URL+f"/overrides?override_id=eq.{override_id}",
        headers={
            'Authorization': 'Bearer ' + token
        },
        json={"state": new_state})
    return redirect_by_code(request, patch_overrides, 'dean:overrides')


def change_grade(request,enrollment_id,new_grade):
    token = request.session.get('token')
    if not token:
        return redirect('home:login')
    patch_grade = requests.patch(
        URL+f"/student_enrollment?student_enrollment_id=eq.{enrollment_id}",
        headers={
            'Authorization': 'Bearer ' + token
        },
        json={"grade": new_grade})
    return redirect_by_code(request, patch_grade, 'dean:allocate_grades')


def redirect_by_code(request, incoming_request, source_page):
    """
    This function is meant to handle error codes.
    Any 4** code will be received by this function and the appropriate page will be rendered

    I know that this is a bit of an unsavory way of implementing this 
    but it's the fastest and I don't have to use my brain
    """
    code = incoming_request.status_code

    if code - 400 >= 0 and code - 400 <= 99:
        messages.add_message(request, messages.WARNING,
                             incoming_request.json()['message'])
        if code == 401:
            return redirect(reverse('home:login'))
        elif code == 403:
            # 403 forbidden means the user is not allowed to access this page
            return render(request, 'student_view/forbidden.html')
        elif code == 404:
            return render(request, 'student_view/notfound404.html')
        else:
            # if the status code is 400 it means it's a bad request so just login again.
            return redirect(reverse(source_page))
    else:
        messages.add_message(request, messages.SUCCESS, "Success")
        return redirect(reverse(source_page))



def overloads(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        # incomplete
        payload = request.POST
        r = requests.post(URL+"/registration", json=payload,
                          headers={'Authorization': 'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            messages.add_message(
                request, messages.WARNING, r.json()['message'])
            return redirect(reverse('home:login'))
        else:
            messages.add_message(request, messages.SUCCESS,
                                 'Succesfully registered section')
            return redirect(reverse('registration'))
    overloads = requests.get(URL+"/overloads?select=*,session(year,semester)",
                             headers={'Authorization': 'Bearer ' + token})
    if 0 <= overloads.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             overloads.json()['message'])
        return HttpResponseRedirect(reverse('home:login'))
    dean_data = request.session.get('dean_data')

    return render(request, "dean_view/overload.html", {
        'overloads': overloads.json(),
        "faculty_data": dean_data
    })



def overload_action(request, new_state, overload_id):
    token = request.session.get('token')
    if not token:
        return redirect('home:login')
    patch_overloads = requests.patch(
        URL+f"/overloads?overload_id=eq.{overload_id}",
        headers={
            'Authorization': 'Bearer ' + token
        },
        json={"state": new_state})
    return redirect_by_code(request, patch_overloads, 'dean:overloads')

def new_session(request):
    return render(request,'registrar_view/create_session.html')


def edit_session(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        # incomplete
        payload = convert(request.POST)
        session_id = payload.pop('session_id')
        r = requests.patch(URL+f"/session?session_id=eq.{session_id}", json=payload,
                          headers={'Authorization': 'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            messages.add_message(
                request, messages.WARNING, r.json()['message'])
            return redirect(reverse('home:login'))
        else:
            messages.add_message(request, messages.SUCCESS,
                                 'Succesfully updated session')
            return redirect(reverse('registrar:edit-session'))
    sessions = requests.get(URL+"/session",
                             headers={'Authorization': 'Bearer ' + token})
    states = requests.get(URL+"/session_states",
                             headers={'Authorization': 'Bearer ' + token})
    if 0 <= sessions.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             sessions.json().get('message'))
        return HttpResponseRedirect(reverse('home:login'))

    return render(request, "registrar_view/edit_session.html", {
        'sessions': sessions.json(),
        'states': states.json()
    })


def new_course(request):
    return render(request,'registrar_view/create_course.html')

def new_section(request):
    return render(request,'registrar_view/create_section.html')
    

def hold(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        # incomplete
        payload = request.POST
        r = requests.post(URL+"/individual_holds", json=payload,
                          headers={'Authorization': 'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= r.status_code - 400 < 100:
            messages.add_message(
                request, messages.WARNING, r.json()['message'])
            return redirect(reverse('home:login'))
        else:
            messages.add_message(request, messages.SUCCESS,
                                 'Succesfully created hold')
            return redirect(reverse('registration'))
    holds = requests.get(URL+"/individual_holds",
                             headers={'Authorization': 'Bearer ' + token})
    if 0 <= holds.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             holds.json()['message'])
        return HttpResponseRedirect(reverse('home:login'))
    return render(request, "registrar_view/hold.html", {
        'holds': holds.json(),
    })

def hold_members(request,hold_id):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    hold_members = requests.get(URL+f"/individual_hold_members?hold_id=eq.{hold_id}",
                     headers={'Authorization': 'Bearer ' + token})
    hold_name = requests.get(URL+f"/individual_holds?hold_id=eq.{hold_id}", headers={'Authorization': 'Bearer ' + token})
    hold_name = hold_name.json()[0].get('hold_name')
    if 0 <= hold_members.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, hold_members.json()['message'])
        return redirect(reverse('home:login'))

    return render(request,'registrar_view/individual_hold_members.html', {
        'members': hold_members.json(),
        'hold_name':hold_name
    })
    

    
def remove_member(request, hold_id, member_id):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    delete_member = requests.delete(URL+f"/individual_hold_members?hold_id=eq.{hold_id}&member_id=eq.{member_id}",
    headers={'Authorization': 'Bearer ' + token}
    )
    if 0 <= delete_member.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, hold_members.json()['message'])
    return redirect(reverse('registrar:hold'))


def delete_hold(request,hold_id):
    token = request.session.get('token')
    if not token:
        return redirect('home:login')
    delete_req = requests.delete(URL+f"/individual_holds?hold_id?hold_id=eq.{hold_id}",
    headers={
        'Authorization':'Bearer ' + token,
        'Prefer':'return=representation'
    })
    return redirect_by_code(request,delete_req,'registrar:hold')



def new_hold(request):
    return render(request,'registrar_view/create_hold.html')

def assign_faculty(request):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    r = requests.get(URL+"/sections?select=section_id,section_number,location,capacity,session(semester,year),courses(course_code,credit_hours,title),section_times(class_dates_abbrev(abbrev),class_times(str_rep)),faculty_assignment(faculty(f_name,l_name,m_name))",
                     headers={'Authorization': 'Bearer ' + token})
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        sections = r.json()



    faculty = requests.get(URL+"/faculty",
                     headers={'Authorization': 'Bearer ' + token})
    if 0 <= faculty.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, faculty.json()['message'])
        return redirect(reverse('home:login'))
    return render(request,'registrar_view/assign-faculty.html', {
        'sections': sections,
        'faculty':faculty.json()
    })


def hold_exceptions(request):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    holdExceptions = requests.get(URL+"/hold_exceptions?select=*,role_holds(hold_name)",
                     headers={'Authorization': 'Bearer ' + token})
    if 0 <= holdExceptions.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, holdExceptions.json()['message'])
        return redirect(reverse('home:login'))
    return render(request,'registrar_view/hold_exceptions.html',{
        'hold_exceptions':holdExceptions.json()
    })


def new_hold_exception(request):
    if not request.session.get('token'):
        return redirect('home:login')
    token = request.session.get('token')
    if request.method == 'POST':
        # incomplete
        payload = convert(request.POST)
        new_exception = requests.post(URL+"/hold_exceptions", json=payload,
                               headers={'Authorization': 'Bearer ' + token})
        # 403 forbidden means the user is not allowed to access this page
        if 0 <= new_exception.status_code - 400 < 100:
            messages.add_message(request, messages.WARNING,
                                 new_exception.json()['message'])
            return redirect(reverse('registrar:new_hold_exception'))
        else:
            messages.add_message(request, messages.SUCCESS,
                                 'Succesfully added exception')
            return redirect(reverse('registrar:new_hold_exception'))
    role_holds = requests.get(URL+"/role_holds",
                             headers={'Authorization': 'Bearer ' + token})
    if 0 <= role_holds.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING,
                             role_holds.json().get('message'))
        return HttpResponseRedirect(reverse('home:login'))

    return render(request, "registrar_view/new_hold_exception.html", {
        'role_holds': role_holds.json(),
    })

def assign(request,section_id,faculty_id):
    if not request.session['token']:
        return redirect(reverse('home:login'))
    token = request.session['token']
    get_assigned = requests.get(
        URL+f"/faculty_assignment?sid=eq.{section_id}",
        headers={'Authorization': 'Bearer ' + token}
    )
    if len(get_assigned.json()) == 0:
        r = requests.post(
        URL+f"/faculty_assignment",
        json={
            "fac_id":faculty_id,
            "sid":section_id
        },
        headers={'Authorization': 'Bearer ' + token}
    )
    else:
        r = requests.patch(
        URL+f"/faculty_assignment?sid=eq.{section_id}",
        json={"fac_id":faculty_id},
        headers={'Authorization': 'Bearer ' + token}
    )
    if 0 <= r.status_code - 400 < 100:
        messages.add_message(request, messages.WARNING, r.json()['message'])
        return redirect(reverse('home:login'))
    else:
        return redirect(reverse('registrar:assign_faculty'))


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