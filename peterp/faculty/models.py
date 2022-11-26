from django.db import models
from datetime import datetime
from django.utils.timezone import now
# Create your models here.
app_label = 'faculty'

class FacultyMessage(models.Model):
    id = models.AutoField(primary_key=True)
    text = models.TextField(verbose_name='text')
    date = models.DateField(default=now())
    seen = models.BooleanField(default=False)
    faculty_id = models.TextField(verbose_name='faculty_id')

    def __str__(self) -> str:
        return f"{self.text}"