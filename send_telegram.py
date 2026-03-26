import urllib.request, urllib.parse, json, sys

token = '8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50'
chat_id = '8724548311'
msg = sys.argv[1] if len(sys.argv) > 1 else 'test'

data = urllib.parse.urlencode({'chat_id': chat_id, 'text': msg}).encode()
req = urllib.request.Request(f'https://api.telegram.org/bot{token}/sendMessage', data=data)
resp = urllib.request.urlopen(req)
result = json.loads(resp.read())
print('OK' if result.get('ok') else 'FAIL')
