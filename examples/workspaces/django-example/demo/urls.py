from django.http import JsonResponse, HttpResponse
from django.urls import path


def index(_request):
    return HttpResponse(
        "<h1>Hello from Django in CodingBooth!</h1>"
        "<p>Try <a href='/api/ping'>/api/ping</a>.</p>"
    )


def ping(_request):
    return JsonResponse({"status": "ok", "message": "pong"})


urlpatterns = [
    path("", index),
    path("api/ping", ping),
]
