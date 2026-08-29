AUTHENTICATION_SOURCES = ['oauth2']
OAUTH2_AUTO_CREATE_USER = True

OAUTH2_CONFIG = [
    {
        'OAUTH2_NAME': 'authelia',
        'OAUTH2_DISPLAY_NAME': 'Authelia',
        'OAUTH2_CLIENT_ID': 'pgadmin',
        'OAUTH2_CLIENT_SECRET': 'REPLACE_WITH_REAL_PASSWORD',
        'OAUTH2_SERVER_METADATA_URL': 'https://auth.fivelabs.tech/.well-known/openid-configuration',
        'OAUTH2_API_BASE_URL': 'https://auth.fivelabs.tech/',
        'OAUTH2_AUTHORIZATION_URL': 'https://auth.fivelabs.tech/api/oidc/authorization',
        'OAUTH2_TOKEN_URL': 'https://auth.fivelabs.tech/api/oidc/token',
        'OAUTH2_USERINFO_ENDPOINT': 'https://auth.fivelabs.tech/api/oidc/userinfo',
        'OAUTH2_SCOPE': 'openid email profile',
        'OAUTH2_ICON': 'fa-lock',
        'OAUTH2_BUTTON_COLOR': '#3253a8',
    }
]