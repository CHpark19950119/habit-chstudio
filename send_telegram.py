"""텔레그램 메시지/파일 전송 유틸리티
사용법:
  python send_telegram.py "메시지"
  python send_telegram.py "캡션" --file photo.jpg
  python send_telegram.py "메시지" --to girlfriend
"""
import urllib.request, urllib.parse, json, sys, os

BOTS = {
    'me': {
        'token': '8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50',
        'chat_id': '8724548311',
    },
    'girlfriend': {
        'token': '8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc',
        'chat_id': '8624466505',
    },
}

def send_message(text, target='me'):
    bot = BOTS[target]
    data = urllib.parse.urlencode({
        'chat_id': bot['chat_id'],
        'text': text,
        'parse_mode': 'HTML',
    }).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{bot['token']}/sendMessage", data=data
    )
    resp = urllib.request.urlopen(req, timeout=10)
    result = json.loads(resp.read())
    return result.get('ok', False)


def send_file(filepath, caption='', target='me'):
    """파일 전송 (사진/문서)"""
    bot = BOTS[target]
    import mimetypes
    mime = mimetypes.guess_type(filepath)[0] or 'application/octet-stream'

    boundary = '----PythonBoundary'
    filename = os.path.basename(filepath)

    # 이미지면 sendPhoto, 아니면 sendDocument
    if mime.startswith('image/'):
        method = 'sendPhoto'
        field = 'photo'
    else:
        method = 'sendDocument'
        field = 'document'

    with open(filepath, 'rb') as f:
        file_data = f.read()

    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="chat_id"\r\n\r\n{bot["chat_id"]}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
        f'Content-Type: {mime}\r\n\r\n'
    ).encode() + file_data + f'\r\n--{boundary}--\r\n'.encode()

    req = urllib.request.Request(
        f"https://api.telegram.org/bot{bot['token']}/{method}",
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary}'},
    )
    resp = urllib.request.urlopen(req, timeout=30)
    result = json.loads(resp.read())
    return result.get('ok', False)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Send Telegram message/file')
    parser.add_argument('message', nargs='?', default='test')
    parser.add_argument('--file', '-f', help='파일 첨부')
    parser.add_argument('--to', '-t', default='me', choices=BOTS.keys())
    args = parser.parse_args()

    if args.file:
        ok = send_file(args.file, caption=args.message, target=args.to)
    else:
        ok = send_message(args.message, target=args.to)

    print('OK' if ok else 'FAIL')
