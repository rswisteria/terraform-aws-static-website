'use strict';

exports.handler = (event, context, callback) => {
  const request = event.Records[0].cf.request;

  const credentials = [
    {user: 'username', pass:'password'}
  ];
  const headers = request.headers;
  if (headers.authorization) {
    const authorized = credentials.some(({user, pass}) => {
      const secret = new Buffer(`${user}:${pass}`).toString('base64');
      return headers.authorization[0].value.split(' ')[1] === secret;
    });

    if (authorized) {
      callback(null, request);
      return;
    }
  }

  callback(null, {
    status: '401',
    statusDescription: '401 Unauthorized',
    headers: {
      'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Basic' }]
    }
  });
}
