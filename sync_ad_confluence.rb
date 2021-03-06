#!/usr/bin/env ruby

require 'trollop'
require 'uri'
require 'net/http'
require 'net/ldap'
require 'json'
require 'open-uri'
require 'nokogiri'
require 'parallel'

opts = Trollop::options do
    banner <<-EOS
Active Directory-to-Confluence user profile synchronizer

Can be used to sync a specific user, or (by default) all AD users with a Confluence account.

Usage: sync_ad_confluence [options] [username]
EOS

    opt :ldaphost, "LDAP hostname, eg. 'mycompany.ds'", :short => 'h', :type=>:string, :default => (ENV['LDAP_HOST'])
    opt :ldapport, "LDAP port number", :short => 'p', :default => (ENV['LDAP_PORT'] || 389)
    opt :binddn, "LDAP bind DN, eg. 'CN=Syncer,OU=ADMIN,DC=Company,DC=ds'", :short => 'D',:type=>:string, :default => (ENV['LDAP_BINDDN'])
    opt :bindpassword, "LDAP bind password", :short => 'w', :type=>:string, :default => (ENV['LDAP_BINDPASSWORD'])
    opt :basedn, "LDAP base DN, eg. 'OU=ADMIN,DC=Company,DC=ds'", :short => 'b', :type=>:string, :default => (ENV['LDAP_BASEDN'])
    opt :confbaseurl, "Confluence base URL, eg. 'http://wiki.company.com'", :short => 'B', :type=>:string, :default => (ENV['CONF_BASEURL'])
    opt :confuser, "Confluence username", :short=>'U', :type => :string, :default => (ENV['CONF_USER'])
    opt :confpassword, "Confluence password", :short=>'P', :type => :string, :default => (ENV['CONF_PASSWORD'])
    opt :verbose, "Print updated profile links", :short=>'v'
end

def get_edituser_actionurl(opts, username)

    pagebody = 
	open(opts[:confbaseurl] + "/admin/users/edituser.action?os_authType=basic&username=#{username}", "X-Atlassian-Token" => "no-check", :http_basic_authentication=>[opts[:confuser], opts[:confpassword]]) { |f| f.read }

    if pagebody =~ /Not Permitted/ then
	raise "Could not find #{username}"
	#$stderr.puts "Could not find #{username}"
	#exit 1
    end
    html = Nokogiri::HTML(pagebody)
    actionurl = html.css("form[name=editUser]").attribute("action").value
    return actionurl
end

# Iterate through AD users
def activedirectory_users(opts, accountname_expr = 'jturner')

    ldap = Net::LDAP.new :host => opts[:ldaphost],
	:port => opts[:ldapport],
	:auth => {
	:method => :simple,
	:username => opts[:binddn],
	:password => opts[:bindpassword]
    
    }

    filter = Net::LDAP::Filter.construct("(&(objectCategory=Person)(memberof=CN=confluence-included,OU=Groups,OU=ADMIN,DC=magicleap,DC=ds)(sAMAccountName=#{accountname_expr})(!(userAccountControl:1.2.840.113556.1.4.803:=2)))")

    ldap.search(
	:base => opts[:basedn],
	:filter => filter,
	:attributes => [:samaccountname, :displayname, :mail, :telephonenumber, :title, :department, :company, :physicaldeliveryofficename, :streetaddress, :l, :st, :postalcode, :co, :thumbnailPhoto, :manager]
    ) 
end

def update_confluence_profile(opts, fields)
    username = fields[:username]
    fullname = fields[:fullname]
    email = fields[:email]
    raise 'username must be present' unless username
    raise 'fullname must be present' unless fullname
    raise 'email must be present' unless email

    actionurl = get_edituser_actionurl(opts, username)
    uri = URI("#{opts[:confbaseurl]}/admin/users/#{actionurl}")
    http = Net::HTTP.new(uri.host, uri.port)
    #http.set_debug_output $stderr
    req = Net::HTTP::Post.new(uri.request_uri)
    req.basic_auth opts[:confuser], opts[:confpassword]
    req.add_field("X-Atlassian-Token", "no-check")

    params = {'os_authType' => 'basic',
	'username' => username,
	'fullName' => fullname,
	# Note: email address is read-only on my LDAP-backed system, so the next line might be removable:
	'email' => email,
	'confirm' => 'Submit'
    }
    fields.each { |k,v| 
	params['userparam-' + k.to_s] = v
    }
    req.set_form_data(params)
    res = http.request(req)
    case res
    when Net::HTTPRedirection
	# We expect to be redirected to the user's profile, and this function returns that link
	if res["Location"] =~ /authenticate\.action/ then
	    $stderr.puts "Please disable Secure administrator sessions aka websudo, at #{opts[:confbaseurl]}/admin/viewsecurityconfig.action"
	    exit 1
	end
	return res["Location"]
    else
	raise "Unexpected HTTP response #{res.value} setting fields #{fields}: #{res}"
    end
end

# Given a hash of activedirectory attributes (eg. {displayname: ["Joe Bloggs"], mail: [joe@example.com], ...}, return a hash of equivalent JIRA user profile HTML form field values.
# 
# Sample keys that might be passed in
#:attributes => [:samaccountname, :displayname, :mail, :telephonenumber, :title, :department, :company, :physicaldeliveryofficename, :streetaddress, :l, :st, :postalcode, :co]
def ad_to_profile(adhash)
    confhash={}
    o,s,l,st,p,co=nil
    title,manager=nil
    adhash.each { |k,v|
	case k
	when :samaccountname
	    confhash[:username]=v[0]
	when :displayname
	    confhash[:fullname]=v[0]
	when :mail
	    confhash[:email]=v[0]
	when :telephonenumber
	    confhash[:phone]=v[0]
	when :jabberid
	    confhash[:im]=v[0]
	when :title
	    title=v[0]
	when :manager
	    if v[0] =~ /^CN=(.*?),/ then
		manager = $1
	    else
		$stderr.puts "Warning: #{confhash[:displayname]} has manager #{v[0]}, which does not conform to expected CN=... pattern"
	    end
	when :department
	    confhash[:department]=v[0]
	when :physicaldeliveryofficename
	    #confhash[:location]=v[0]
	    o=v[0]
	when :streetaddress
	    s=v[0]
	when :l
	    l=v[0]
	when :st
	    st=v[0]
	when :postalcode
	    p=v[0]
	when :co
	    co=v[0]
	end
    }
    # Location is a composite of various AD fields
    # No longer - Location is now just the Office address. see https://mail.google.com/mail/u/0/#inbox/148483cc3d1132ad
    #confhash[:location]=[o,s,l,st,p,co].select{|x|x}.join(", ")
    confhash[:location]='' + (o || '') + ' - ' + [l,st].select{|x|x}.join(", ")
    # Likewise, Position is a composite of title and manager
    confhash[:position]=title if title
    confhash[:position]=confhash[:position] +", reporting to " + manager if manager && confhash[:position]
    return confhash
end

username=ARGV.shift || '*'
Parallel.map( activedirectory_users(opts, username), :in_processes=>10 ) { |entry|

    profilefields = ad_to_profile(entry)
    if !profilefields[:email] then
	$stderr.puts " *** Skipping #{profilefields[:username]} as it has no email record" if opts[:verbose]
    else
	begin
		profileurl = update_confluence_profile(opts, profilefields)
		profileurl.gsub! /;jsessionid=.*?(?=\?)/, '' # Get rid of jsessionid for readability
		puts "#{username}: set profile: #{profilefields}" if opts[:verbose]
	rescue Exception => e
		$stderr.puts e
	end
    end
}
