package JSDoc;

=head1 NAME

JSDoc - parse JavaScript source file for JSDoc comments

=head1 SYNOPSIS
	
	parse_jsdoc_source(\$js_source, \&print_comment);
	
	sub print_comment {
		my($obj_name, $type, $code, $comment_ref) = @_;
		my %comment = %{$comment_ref};
		print "$obj_name $type\n";
		print "$code\n";
		if ($comment{summary}) {
			print "summary: $comment{summary}\n";
		}
		if ($comment{args}) {
			my %args = %{$comment{args}};
			foreach (keys %args) {
				print "$_: $args{$_}\n";
			}
		}
		if ($comment{vars}) {
			my %vars = %{$comment{vars}};
			foreach (keys %vars) {
				print "$_: ".join(", ", @{$vars{$_}})."\n";
			}
		}
	}
	
=head1 DESCRIPTION

The C<parse_jsdoc_source> function requires a ref to string holding the source code
of a javascript object file, and a ref to a callback subroutine to handle any found
JSDoc elements. The source file is parsed and the callback is called as each
element is found.

=head1 AUTHOR

mmathews@jscan.org

=cut

require 5.000;
use Carp;
use Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(parse_jsdoc_source);

sub parse_jsdoc_source {

#params:
	# a reference to a scalar, the js object source code
	my $js_src = ${$_[0]};
	# a reference to a sub, used as a callback
	my $handle_comment = $_[1];
	
	# perlify os line-endings
	$js_src =~ s/(\r\n|\r)/\n/g;
	
	while ($js_src =~ m!
							/\*\*		# the start of a JSDoc comment
							(.*?)		# everything within that comment
							\*/			# the end of a JSDoc comment
							\s*\n\s*	# possible whitespace and a newline
							(.*?)		# everything on the following line
							(\n|;|//)	# up to one of these statement terminators
					   !gsx) {
		# grab the contents of a doc-comment and the line of code that follows
		my ($doc, $code) = ($1, $2);
		
		# trim leading whitespace and asterisks from doc-comment
		$doc =~ s/^[\t \*]*//gm;
		
		# is the code a constructor def? like this:
		# ObjectName = function(arg, arg) {
		# function ObjectName(arg, arg) {
		if ($code =~ m!^\s*([A-Z]\w*)\s*=\s*function\s*(\(.*?\))\w*\{?!
		or $code =~ m!^\s*function\s+([A-Z]\w*)\s*(\(.*?\))\w*\{?!) {
			&$handle_comment($1, "CONSTRUCTOR", "new $1$2", parse_jsdoc_comment($doc));
		}
		
		# is the code a property def? like this:
		# ObjectName.prototype.property = function(arg, arg)
		# ObjectName.prototype.property = "value"
		if ($code =~ m!^\s*([A-Z]\w*)\.prototype\.(\w+)(\s*=\s*function\s*(\(.*?\)))?!) {
			if ($4) {
				&$handle_comment($1, "METHOD", "$1.$2$4", parse_jsdoc_comment($doc));
			}
			else {
				&$handle_comment($1, "PROPERTY", "$1.$2", parse_jsdoc_comment($doc));
			}
		}

	}
}

sub parse_jsdoc_comment {
	my $doc = shift;
	
	# remember each part that is parsed
	my %parsed = ();
	
	# the first paragraph could be a summary statement
	# a paragraph may follow of variable defs (variable names start with "@")
	my ($summary, $variable_str) = $doc =~ /^\s*([^@].*?)\s*(?:\n\n\s*(.*)\s*)?$/gs;
	
	$parsed{summary} = $summary;

	# two types of variable def can be dealt with here:
	# a @argument has a two-part value -- the arg name and a description
	# all other @<variables> only have a single value each (although there may
	# be many variables with the same name)
	if($variable_str) {
		my %args = ();
		my %vars = ();
		while ($variable_str =~ /(?:^|\s*\n)\@argument\s+(\w+)\s+(\S.*?)(?=\n\n|\n@|$)/gs) {
			$args{$1} = $2;
		}
		$parsed{args} = \%args;

		while ($variable_str =~ /(?:^|\s*\n)\@(?!argument)(\w+)\s+(\S.*?)(?=\n\n|\n@|$)/gs) {
			$vars{$1} = [] unless defined $vars{$1};
			push(@{$vars{$1}}, $2);
		}
		$parsed{vars} = \%vars;
	}
	return \%parsed;
}

1;
