from django.shortcuts import render
from wsgiref import headers
from django.shortcuts import redirect, render
import requests
import json
from django.contrib import messages
from django.urls import reverse

from django.http import HttpResponseRedirect

from student.models import StudentMessage
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
        faculty_data = requests.get(
            URL+"/faculty", headers={
                'Authorization': 'Bearer ' + token,
                'Accept': 'application/vnd.pgrst.object+json'
            })
        print(faculty_data.json())
        # if the status_code is 401 it means the token is expired. Redirect the user to logout and create an error message
        fac_id = faculty_data.json()['faculty_id']
        semester_schedule = requests.get(
            URL+f"/session?select=*,sections(*,section_times(class_dates_abbrev(abbrev),class_times(str_rep)),course:courses(*),faculty_assignment!inner(*))&sections.faculty_assignment.fac_id=eq.{fac_id}&status=eq.active&state_id=gt.2", headers={
                'Authorization': 'Bearer ' + token,
                'Accept': 'application/vnd.pgrst.object+json'
            })
        if faculty_data.status_code == 401:
            messages.add_message(request, messages.WARNING,
                                 "Session expired, please login again")
            return redirect(reverse('faculty:logout'))
        # for the current use case if there is no 401 error then the data is valid
        # this probably will not hold in production but suffices for now
        else:
            # cache the important data about the current use to avoid making repeated api calls
            request.session['faculty_data'] = faculty_data.json()
            request.session['semester_schedule'] = semester_schedule.json()
        role = requests.get(URL+"/get_role")
        request.session['role'] = role.json()
        return render(request, "faculty_view/index.html", {
            'faculty_data': faculty_data.json(),
            'semester_schedule': semester_schedule.json(),
        })


def semester_schedule(request):
    # if there's no faculty_data or profile then the user is not logged in, redirect to login
    if not request.session.get('faculty_data') or not request.session.get('semester_schedule'):
        return redirect(reverse('home:login'))
    if not request.session['token']:
        return redirect(reverse('home:login'))
    semester_schedule = request.session.get('semester_schedule')
    faculty_data = request.session.get('faculty_data')
    return render(request, 'faculty_view/semester.html', {
        'semester_schedule': semester_schedule,
        'faculty_data': faculty_data,
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
    faculty_data = request.session.get('faculty_data')
    on_hold = requests.post(
        URL+"/rpc/user_hold_check",
        headers={'Authorization':'Bearer ' + token, },
        json={"restricted_object":'student_enrollment',"operation":"update"}
        )
    on_hold = on_hold.json()
    return render(request, "faculty_view/allocate-grade.html", {
        'grades': grades.json(),
        "faculty_data": faculty_data,
        "on_hold":on_hold
    })


def profile(request):
    return render(request, 'faculty_view/profile.html')


def sections(request):
    if not request.session.get('faculty_data') or not request.session.get('semester_schedule'):
        return redirect(reverse('home:login'))
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

    faculty_data = request.session.get('faculty_data')
    return render(request, 'faculty_view/sections.html', {
        'faculty_data': faculty_data,
        'sections': sections,
    })


def courses(request):
    if not request.session.get('faculty_data') or not request.session.get('semester_schedule'):
        return redirect(reverse('home:login'))
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

    faculty_data = request.session.get('faculty_data')
    return render(request, 'faculty_view/courses.html', {
        'courses': courses,
        'faculty_data': faculty_data,
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
    faculty_data = request.session.get('faculty_data')

    return render(request, "faculty_view/override.html", {
        'overrides': overrides.json(),
        "faculty_data": faculty_data
    })


def logout_user(request):
    # delete the session data and redirect to login. This makes the system forget there's ever been a person logged in
    request.session.flush()
    return redirect(reverse('home:login'))


def section_records(request, section_id):
    # if there's no student_data or profile then the user is not logged in, redirect to login
    if not request.session.get('faculty_data'):
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
    faculty_data = request.session.get('faculty_data')
    return render(request, 'faculty_view/semester_records.html', {
        'section_data': section_data,
        'faculty_data': faculty_data

    })
    "sections?select=*,session(semester,year),student_enrollment!inner(students(first_name,middle_name,last_name))"
    return render(request, 'faculty_view/semester_records.html')


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
    override_details = requests.get(
        URL + f"/overrides?select=section_id,student_id,section:sections(course:courses(course_code))&override_id=eq{override_id}",
        headers={
            'Authorization': 'Bearer ' + token,
            'Accept': 'application/vnd.pgrst.object+json'

        }   
    )
    override_details = override_details.json() if override_details.status_code == 200 else None
    if override_details:
        message = StudentMessage(
            text=f"Override request for {override_details.get('section').get('course').get('course_code')} {new_state}",
            student_id=override_details.get('student_id'))
        message.save()
    return redirect_by_code(request, patch_overrides, 'faculty:overrides')


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
    return redirect_by_code(request, patch_grade, 'faculty:allocate_grades')


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

