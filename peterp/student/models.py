from django.db import models
from datetime import datetime
from django.utils.timezone import now
# Create your models here.
app_label = 'student'

class StudentMessage(models.Model):
    id = models.AutoField(primary_key=True)
    text = models.TextField(verbose_name='text')
    date = models.DateField(default=now())
    seen = models.BooleanField(default=False)
    student_id = models.TextField(verbose_name='student_id')

    def __str__(self) -> str:
        return f"{self.text}"