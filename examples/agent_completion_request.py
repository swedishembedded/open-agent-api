import open_agent_api
from open_agent_api.api import default_api
from open_agent_api.models.agent_completion_request import AgentCompletionRequest
from open_agent_api.models.environment import Environment
from open_agent_api.models.message import Message

# Configure API client
configuration = open_agent_api.Configuration(host="http://localhost:8007")
# Add API key for authorization
configuration.api_key['ApiKey'] = 'YOUR_API_KEY'
# Uncomment the following line to set API key prefix: 'Bearer' for example
# configuration.api_key_prefix['ApiKey'] = 'Bearer'
api_client = open_agent_api.ApiClient(configuration)
api_instance = default_api.DefaultApi(api_client)

# Create request
request = AgentCompletionRequest(
    environment=Environment(
        working_directory="/path/to/working/dir",
        platform="linux"
    ),
    messages=[
        Message(role="user", content="Hello, agent!")
    ]
)

# Make API call
response = api_instance.agent_agent_id_post(agent_id="search", agent_completion_request=request)