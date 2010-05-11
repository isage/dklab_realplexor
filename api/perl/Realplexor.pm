package Realplexor;
use strict;
use JSON;
use IO::Socket;


#$host, $port, $namespace = null, $identifier = "identifier"
sub new
{
    my $class=shift;
    my $options=shift;
    $options->{identifier} = $options->{identifier} || 'identifier';
    my $self = bless $options, $class;
    return $self;
}

sub logon
{
    my ($self,$login,$password)=@_;
    $self->{login}=$login;
    $self->{password}=$password;
    $self->{namespace}=$login.'_'.$self->{namespace};
}

sub send
{
    my $self=shift;
    my $ids=shift;
    my $data=shift;
    my $sofid=shift || undef;
    $data=to_json($data, {utf8 => 1,allow_nonref=>1});
    my @pairs;
    if (ref $ids eq 'HASH')
    {
        while (my($id,$cur)=each(%{$ids}))
        {
            warn 'Id must be alphanumeric' if($id!~/^\w+$/);
            $id=$self->{namespace}.$id;
            if ($cur ne undef)
            {
                warn 'Id must be alphanumeric' if($cur!~/^[0-9]+$/);
                push @pairs,"$cur:$id";
            }
            else
            {
                push @pairs,$id;
            }
        }
        
    }
    else
    {
        push @pairs,$ids;
    }
    if (ref $sofid eq 'ARRAY')
    {
        foreach my $soid(&$sofid)
        {
            push @pairs,"*".$self->{namespace}.$soid;
        }
    }
    $self->_send(join(",", @pairs), $data);
}


sub _sendCmd
{
    my $self=shift;
    my $d=shift;
    return $self->_send(undef, $d."\n");
}

sub cmdOnline
{
    my $self=shift;
    my @prefixes=shift || undef;
    if (length $self->{namespace})
    {
        my $key=0;
        foreach my $pref(@prefixes)
        {
            $prefixes[$key]=$self->{namespace}.$pref;
            $key++;
        }
    }
    my $resp = $self->_sendCmd("online" . ( @prefixes ? " " . join(" ", @prefixes) : ""));
    return () if (length $resp <=0);
    my @resps=split(',',$resp);
    if (length $self->{namespace})
    {
        my $i=0;
        foreach my $respo(@resps)
        {
            if ($respo=~/$self->{namespace}/)
            {
                $resps[$i] = substr($respo, length $self->{namespace});
            }
            $i++;
        }
    }
    return @resps;
}

sub cmdWatch
{
    my $self=shift;
    my $from_pos=shift || 0;
    my @prefixes=shift || undef;
    warn 'Position must be numeric' if($from_pos!~/^\d+$/);
    if (length $self->{namespace})
    {
        my $key=0;
        foreach my $pref(@prefixes)
        {
            $prefixes[$key]=$self->{namespace}.$pref;
            $key++;
        }
    }
    my $resp = $self->_sendCmd("watch $from_pos" . (@prefixes ? " " . join(" ", @prefixes) : ""));
    return () if (length $resp <=0);
    my @resps = explode("\n", $resp);
    my @events = ();
    foreach my $line (@resps)
    {
        my @m;
        if (@m=($line=~m/^ (\w+) \s+ ([^:]+):(\S+) \s* $/sx))
        {
            warn "Cannot parse the event: \"$line\"";
            next;
        }
        my ($event, $pos, $id) = ($m[1], $m[2], $m[3]);
        if ($from_pos && length($self->{namespace}) && $id=~/$self->{namespace}/) {
            $id = substr($id, strlen($self->{namespace}));
        }
        push @events, {'event' => $event, 'pos' => $pos, 'id' => $id};
    }
    return @events;
}

sub _send
{
    my ($self,$id,$body)=@_;
    my $headers = "X-Realplexor: ".$self->{identifier}."=".($self->{login} ? $self->{login}.":". $self->{password}.'@' : '').($id ? $id : "")."\r\n";
    my $data = "POST / HTTP/1.1\r\n"."Host: ".$self->{host}."\r\n"."Content-Length: ".length($body)."\r\n".$headers."\r\n".$body;

    my $sock = IO::Socket::INET->new(
        PeerAddr => $self->{host},
        PeerPort => $self->{port},
        Proto    => 'tcp'
    ) || die "can't connect to ".$self->{host}.":".$self->{port}."\n";
    $sock->print($data);
    $sock->shutdown(1);
    my @lines = <$sock>;

    close $sock;
    my $result=join("\n",@lines);
    if ($result)
    {
        my ($rheaders, $rbody) = split(/\r?\n\r?\n/s, $result, 2);
        my @m;
        my @m1;
        if (!(@m=($rheaders=~m{^HTTP/[\d.]+ \s+ ((\d+) [^\r\n]*)}six)))
        {
                warn "Non-HTTP response received:\n".$result;
        }
        if ($m[2] ne '200') {
            warn "Request failed: " . $m[1] . "\n" . $rbody;
        }
        if (!(@m1=($rheaders=~m/^Content-Length: \s* (\d+)/mix)))
        {
            warn "No Content-Length header in response headers:\n" . $headers;
        }
        my $needLen = $m1[1];
        my $recvLen = length($rbody);
        if ($needLen != $recvLen) {
            warn "Response length ($recvLen) is different than specified in Content-Length header ($needLen): possibly broken response\n";
        }
        return $rbody;
    }
    return '';
}

return 1;

