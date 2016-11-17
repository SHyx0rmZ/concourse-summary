require "http/client"
require "json"
require "kemal"

require "./concourse-summary/*"

alias GroupHash = Hash(String, Hash(String, Array(String)?)?)
REFRESH_INTERVAL = (ENV["REFRESH_INTERVAL"]? || 30).to_i
GROUPS = Hash(String, GroupHash).from_json(ENV["CS_GROUPS"]? || "{}")

def setup(env)
  refresh_interval = REFRESH_INTERVAL
  username = env.store["credentials_username"]?
  password = env.store["credentials_password"]?

  login_form = env.params.query.has_key?("login_form")
  if login_form && (username.to_s.size == 0 || password.to_s.size == 0)
    raise Unauthorized.new
  end

  ignore_groups = env.params.query.has_key?("ignore_groups")
  {refresh_interval,username,password,ignore_groups,login_form}
end

def process(data, ignore_groups)
  if ignore_groups
    data = MyData.remove_group_info(data)
  end
  statuses = MyData.statuses(data)
end

get "/host/:host/**" do |env|
  refresh_interval,username,password,ignore_groups,login_form = setup(env)
  host = env.params.url["host"]

  data = MyData.get_data(host, username, password, nil, login_form)
  statuses = process(data, ignore_groups)

  json_or_html(statuses, "host")
end

get "/group/:key" do |env|
  refresh_interval,username,password,ignore_groups,login_form = setup(env)

  hosts = GROUPS[env.params.url["key"]]
  hosts = hosts.map do |host, pipelines|
    data = MyData.get_data(host, username, password, pipelines)
    data = MyData.filter_groups(data, pipelines)
    statuses = process(data, ignore_groups)
    { host, statuses }
  end

  json_or_html(hosts, "group")
end

get "/" do |env|
  hosts = (ENV["HOSTS"]? || "").split(/\s+/)
  groups = GROUPS.keys

  json_or_html(hosts, "index")
end

Kemal.config.add_handler ExposeUnauthorizedHandler.new
Kemal.run
