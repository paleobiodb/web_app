
use Dancer;

use Wing;
use Wing::Web;



post '/login' => sub {
    
    return template 'account/login', { error_message => 'You must specify a username or email address.'} unless params->{login};
    return template 'account/login', { error_message => 'You must specify a password.'} unless params->{password};
    
    my $username = params->{login};
    my $password = params->{password};
    my $schema = Wing->db;
    
    my $user = $schema->resultset('User')->search({username => $username },{rows=>1})->single;
    
    unless ( defined $user )
    {
	my @results = $schema->resultset('User')->search({email => $username });

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
    
    my $authorizer_no = $user->get_column('authorizer_no');
    my $person_no = $user->get_column('person_no');
    my $role = $user->get_column('role');
    
    # $$$ add check for proper authent entry
    
    if ( $authorizer_no )
    {
	if ( $authorizer_no ne $person_no )
	{
	    my $dbh = $schema->storage->dbh;
	    
	    my ($check_no) = $dbh->selectrow_array("SELECT authorizer_no FROM authents WHERE authorizer_no = $authorizer_no
						and enterer_no = $person_no");
	    
	    if ( $check_no )
	    {
		$user->login_role('enterer');
		$user->login_authorizer_no($authorizer_no);
		return login($user);
	    }
	}
	
	elsif ( $role eq 'authorizer' )
	{
	    $user->login_role('authorizer');
	    $user->login_authorizer_no($authorizer_no);
	    return login($user);
	}
    }

    elsif ( $role eq 'authorizer' )
    {
	$user->set_column('authorizer_no', $person_no);
	$user->login_role('authorizer');
	$user->login_authorizer_no($person_no);
	return login($user);
    }
    
    elsif ( $role eq 'enterer' )
    {
	my $dbh = $schema->storage->dbh;
	
	my ($authorizer_no) = $dbh->selectrow_array("SELECT authorizer_no FROM authents WHERE enterer_no = $person_no LIMIT 1");
	
	if ( $authorizer_no )
	{
	    $user->set_column('authorizer_no', $authorizer_no);
	    $user->login_role('enterer');
	    $user->login_authorizer_no($authorizer_no);
	    return login($user);
	}
    }
    
    $user->login_role('guest');
    $user->login_authorizer_no(0);
    return login($user);
    
    # if ( my $auth_name = params->{authorizer} )
    # {
    # 	my $auth = find_user($auth_name);
	
    # 	if ( !defined $auth || $auth eq 'NONE' )
    # 	{
    # 	    return template 'account/login', { error_message => 'Authorizer not found.' };
    # 	}

    # 	elsif ( $auth eq 'MULTIPLE' )
    # 	{
    # 	    return template 'account/login', { error_message => 'Authorizer is ambiguous.' };
    # 	}

    # 	unless ( authorizer_ok($user, $auth) )
    # 	{
    # 	    return template 'account/login', { error_message => 'You do not have permission from that authorizer.' };
    # 	}
	
    # 	$user->login_role('enterer');
    # 	$user->login_authorizer_no($auth->person_no);
    # 	return login($user);
    # }
    
    # elsif ( $user->role =~ /authorizer/ )
    # {
    # 	$user->login_role('authorizer');
    # 	$user->login_authorizer_no($user->person_no);
    # 	return login($user);
    # }
    
    # elsif ( $user->role =~ /admin/ )
    # {
    # 	$user->login_role('guest');
    # 	$user->login_authorizer_no(0);
    # 	return login($user);
    # }
    
};


sub find_user {
    
    my ($name) = @_;

    my ($first, $last);
    
    if ( $name =~ qr{ ([^,]+) , \s* (.*) }xs )
    {
	$last = $1;
	$first = $2;
	
	$first =~ s/[.]*$/%/;
	
	my (@results) = Wing->db->resultset('User')->search({first_name => { -like => $first }, last_name => { -like => $last } });
	
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
	
	my (@results) = Wing->db->resultset('User')->search({first_name => { -like => "$first%" }, last_name => { -like => $last } });
	
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


get '/account/enterers' => sub {
    my $user = get_user_by_session_id();
    template 'account/enterers', { current_user => $user, };
};



1;
