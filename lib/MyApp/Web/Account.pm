
use Dancer;

use Wing;




post '/login' => sub {
    
    return template 'account/login', { error_message => 'You must specify a username or email address.'} unless params->{login};
    return template 'account/login', { error_message => 'You must specify a password.'} unless params->{password};
    
    my $username = params->{login};
    my $password = params->{password};
    
    my $user = Wing->db->resultset('User')->search({username => $username },{rows=>1})->single;
    
    unless ( defined $user )
    {
	my @results = Wing->db->resultset('User')->search({email => $username });

	if ( @results == 1 )
	{
	    $user = $results[0];
	}

	elsif ( @results > 1 )
	{
	    return template 'account/login', { error_message => 'Email is not unique.' };
	}
    }
    
    unless ( defined $user )
    {
	$user = find_user($username);
	
	if ( !defined $user || $user eq 'NONE' )
	{
	    return template 'account/login', { error_message => 'User not found.'};
	}
	
	elsif ( $user eq 'MULTIPLE' )
	{
	    return template 'account/login', { error_message => 'User name is ambiguous.' };
	}
    }
    
    # validate password
    if (! $user->is_password_valid($password)) {
	return template 'account/login', { error_message => 'Password incorrect.'};
    }
    
    # check for a valid authorizer
    
    if ( my $auth_name = params->{authorizer} )
    {
	my $auth = find_user($auth_name);
	
	if ( !defined $auth || $auth eq 'NONE' )
	{
	    return template 'account/login', { error_message => 'Authorizer not found.' };
	}

	elsif ( $auth eq 'MULTIPLE' )
	{
	    return template 'account/login', { error_message => 'Authorizer is ambiguous.' };
	}

	unless ( authorizer_ok($user, $auth) )
	{
	    return template 'account/login', { error_message => 'You do not have permission from that authorizer.' };
	}
	
	$user->login_role('enterer');
	$user->login_authorizer_no($auth->person_no);
	return login($user);
    }
    
    elsif ( $user->role =~ /authorizer/ )
    {
	$user->login_role('authorizer');
	$user->login_authorizer_no($user->person_no);
	return login($user);
    }
    
    # elsif ( $user->role =~ /admin/ )
    # {
    # 	$user->login_role('guest');
    # 	$user->login_authorizer_no(0);
    # 	return login($user);
    # }
    
    else
    {
	$user->login_role('guest');
	$user->login_authorizer_no(0);
	return login($user);
    }
};


sub find_user {
    
    my ($name) = @_;

    my ($first, $last);
    
    if ( $name =~ qr{ ([^,]+) , \s* (.*) }xs )
    {
	$last = $1;
	$first = $2;
	
	$first =~ s/[.]*$/%/;
	
	my (@results) = Wing->db->resultset('User')->search_like({first_name => $first, last_name => $last });
	
	if ( @results == 1 )
	{
	    return $results[0];
	}
	
	elsif ( @results == 0 )
	{
	    return 'NONE';
	}

	else
	{
	    return 'MULTIPLE';
	}
    }
    
    elsif ( $name =~ qr{ (\w+) (?: [.] \s* | \s+ ) (.*) }xs )
    {
	$first = $1;
	$last = $2;
	
	my (@results) = Wing->db->resultset('User')->search_like({first_name => "$first%", last_name => $last });
	
	if ( @results == 1 )
	{
	    return $results[0];
	}
	
	elsif ( @results == 0 )
	{
	    return 'NONE';
	}

	else
	{
	    return 'MULTIPLE';
	}
    }
    
    else
    {
	my (@results) = Wing->db->resultset('User')->search({last_name => $name });
	
	if ( @results == 1 )
	{
	    return $results[0];
	}
	
	elsif ( @results == 0 )
	{
	    return 'NONE';
	}

	else
	{
	    return 'MULTIPLE';
	}
    }
};


sub login {
    
    my ($user) = @_;
    
    my $session = $user->start_session({ api_key_id => Wing->config->get('default_api_key'), ip_address => request->remote_address });
    set_cookie session_id   => $session->id,
                expires     => '+5y',
                http_only   => 0,
                path        => '/';
    if (params->{sso_id}) {
        my $cookie = cookies->{sso_id};
        my $sso_id = $cookie->value if defined $cookie;
        $sso_id ||= params->{sso_id};
        my $sso = Wing::SSO->new(id => $sso_id, db => Wing->db());
        $sso->user_id($user->id);
        $sso->store;
        if ($sso->has_requested_permissions) {
            return redirect $sso->redirect;
        }
        else {
            return redirect '/sso/authorize?sso_id='.$sso->id;
        }
    }
    my $cookie = cookies->{redirect_after};
    my $uri = $cookie->value if defined $cookie;
    $uri ||= params->{redirect_after} || '/classic';
    return redirect $uri;
}


sub authorizer_ok {

    my ($user, $authorizer) = @_;
    
    my @auth_list = $user->registered_authorizers();

    foreach my $a (@auth_list)
    {
	if ( $authorizer->person_no eq $a->person_no )
	{
	    return 1;
	}
    }

    return;
}


1;
