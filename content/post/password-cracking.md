+++
date = "2013-03-08T00:00:00-05:00"
draft = false
title = "Password Cracking on Amazon EC2"

+++

## Introduction

In one of my courses at McMaster University - [Computer Networks and
Security][course] - the professor gave a challenge in class. The first person
to crack a `crypt()` hash would get a 3% bonus on their final grade, and the
first person to crack a `md5crypt()`-based hash would get a 7% bonus on their
final grade. I cracked the `crypt()` password while the class was still going,
by using [John the Ripper][jtr] and a decent wordlist that I had lying around
on this server. The `md5crypt()` one would be much harder to do on a cheap VPS,
though, and my MacBook Air is nowhere near powerful enough to be of use. So,
after I got home, I decided that I was going to try and use Amazon EC2 to gain
those extra percent.  Specifically, Amazon provides a [GPU Instance][gpu],
which comes with two NVIDIA Tesla M2050 GPUs attached. After a bit of work, I
managed to get [oclHashcat-plus][hashcat], one of the world's fastest GPU-based
crackers, working on it.  It wasn't trivial, though, so here's how I did it.

[course]: http://www.cas.mcmaster.ca/~soltys/cs3c03-w13/index.html
[jtr]: http://www.openwall.com/john/
[gpu]: https://aws.amazon.com/ec2/instance-types/#gpu
[hashcat]: http://hashcat.net/oclhashcat-plus/

## Installing CUDA

First, you need to start the instance. Go to the EC2 management console, and
start the instance, using AMI ami-f4039f9d. This is the official Ubuntu for
Cluster Computing 11.10. Note that the quickstart page provides 12.04 or 12.10,
both of which present problems (no official NVIDIA driver, newer version of
GCC, etc.).

**EDIT**: I've noticed that some people have trouble launching this AMI. The
short way is to click [this link][ami]. The longer, but perhaps more useful way is as
follows:

1. Go to the [Ubuntu Amazon EC2 AMI Locator][amiloc]
2. Filter by "oneiric" under the "Name" column, and "hvm" under the "Instance
   Type" column.
3. Pick the region you want to launch the instance in, and click the AMI ID,
   which should bring up the EC2 Console, letting you launch the given
   instance.
4. Launch the AMI on the "Cluster GPU" instance (cg1.4xlarge).

Once the instance is started, SSH into it, and install the basics:

```
sudo apt-get update
sudo apt-get install gcc g++ build-essential linux-headers-`uname -r`
```

Now, we need to install [GLUT][glut]:

```
sudo apt-get install freeglut3 freeglut3-dev
```

Next, the CUDA toolkit for this version of Linux. You should install everything
(yes, including the samples):

```
wget http://developer.download.nvidia.com/compute/cuda/5_0/rel-update-1/installers/cuda_5.0.35_linux_64_ubuntu11.10-1.run
chmod a+x cuda_5.0.35_linux_64_ubuntu11.10-1.run
sudo sh ./cuda_5.0.35_linux_64_ubuntu11.10-1.run --verbose
```

If there are any problems, check them out on Google - chances are, someone else
has run into this already. Note that you need version 4.6 of GCC - the install
checks for the version, and 4.7 will cause it to fail (this is especially true
if you're using 12.04 or 12.10). Also, you have to build the kernel module with
the same version of GCC as the kernel was compiled with.

Anyway, once the toolkit is compiled, we need to set up the environment so that
we can run CUDA programs. Open `/etc/environment` in your favorite editor, and
append `/usr/local/bin/cuda` to the PATH variable. Next, create
`/etc/ld.so.conf.d/cuda.conf` in your editor, add the following 2 lines, and
save it:

```
/usr/local/cuda/lib64
/usr/local/cuda/lib
```

Run `sudo ldconfig` to update things, and the environment should be all set up.
You can verify this by running the deviceQuery sample that comes with CUDA (you
did install it above, right?):

```
cd /usr/local/cuda/samples/1_Utilities/deviceQuery
sudo make
sudo ./deviceQuery
```

This should show you the two NVIDIA M2050 GPUs that are attached. If you don't
see them, or you have an error, you need to fix things before continuing.

[ami]: https://console.aws.amazon.com/ec2/home?region=us-east-1#launchAmi=ami-f4039f9d
[amiloc]: http://cloud-images.ubuntu.com/locator/ec2/
[glut]: http://www.opengl.org/resources/libraries/glut/

## Installing oclHashcat-plus

Ok, once you reached this point, you should have a working CUDA install. Now
that you've got this, you can grab oclHashcat-plus:

```
sudo apt-get install p7zip-full
wget http://hashcat.net/files/oclHashcat-plus-0.13.7z
7za x oclHashcat-plus-0.13.7z
cd oclHashcat-plus-0.13
```

Note that, despite the fact the project is called "oclHashcat", we're actually
going to be using the "cudaHashcat" command. You can verify everything
extracted correctly by trying to crack a simple hash. Here's the full example
and output from my tests:

```
ubuntu@ip-10-16-20-96:~/hashcat/oclHashcat-plus-0.13$ echo -n AndrewD | md5sum > hashes.test
ubuntu@ip-10-16-20-96:~/hashcat/oclHashcat-plus-0.13$ sudo ./cudaHashcat-plus64.bin --force --hash-type=0 -1 ?l?u -a 3 hashes.test ?1?1?1?1?1?1?1
cudaHashcat-plus v0.13 by atom starting…

Hashes: 1 total, 1 unique salts, 1 unique digests
Bitmaps: 8 bits, 256 entries, 0x000000ff mask, 1024 bytes
Workload: 256 loops, 80 accel
Watchdog: Temperature abort trigger set to 90c
Watchdog: Temperature retain trigger set to 80c
Device #1: Tesla M2050, 2687MB, 1147Mhz, 14MCU
Device #2: Tesla M2050, 2687MB, 1147Mhz, 14MCU
Device #1: Kernel ./kernels/4318/m0000_a3.sm_20.ptx
Device #2: Kernel ./kernels/4318/m0000_a3.sm_20.ptx

[s]tatus [p]ause [r]esume [b]ypass [q]uit =>

e974e36b5b0f062d86020252edd8ad51:AndrewD

Session.Name...: cudaHashcat-plus
Status.........: Cracked
Input.Mode.....: Mask (?1?1?1?1?1?1?1)
Hash.Target....: e974e36b5b0f062d86020252edd8ad51
Hash.Type......: MD5
Time.Started...: Fri Mar 8 17:47:09 2013 (4 mins, 39 secs)
Speed.GPU.#1...: 1159.8M/s
Speed.GPU.#2...: 1161.0M/s
Speed.GPU.# ...: 2320.9M/s
Recovered......: 1/1 (100.00%) Digests, 1/1 (100.00%) Salts
Progress.......: 645335613440/1028071702528 (62.77%)
Rejected.......: 0/645335613440 (0.00%)
HWMon.GPU.#1...: 0% Util, -1c Temp, -1% Fan
HWMon.GPU.#2...: 7% Util, -1c Temp, -1% Fan

Started: Fri Mar 8 17:47:09 2013
Stopped: Fri Mar 8 17:51:55 2013
ubuntu@ip-10-16-20-96:~/hashcat/oclHashcat-plus-0.13$
```

If you can do the same, then things are working perfectly.

## Cracking Tips

In addition to brute-force, I'd recommend grabbing a wordlist to use. This is
much faster than running through the entire keyspace, and can often make the
difference between cracking and not cracking a hash. If you want to do this,
grab rtorrent, which is a fast, console-based torrent client, and a wordlist.
I've heard good things about this wordlist, for example. Either way, here's
what I did:

```
cd /mnt
sudo mkdir wordlist
sudo chown ubuntu:ubuntu wordlist
cd wordlist
rtorrent
```

Then, inside rtorrent, press Backspace, paste a magnet link, hit Enter, and
wait for the torrent to download (and then Ctrl-Q to exit). If the torrent
contains a RAR file, here's a couple of quick steps on how to extract it:

1. Open `/etc/apt/sources.list` in your favorite editor.
2. Add "multiverse" to the end of any lines that start with "deb" and end with
   "universe". There should be 2 of these.
3. `sudo apt-get update`
4. `sudo apt-get install unrar`
5. `unrar x YOUR_RAR_FILE.rar`

Once you have a wordlist, you can use it with oclHashcat like so:

```
./cudaHashcat-plus64.bin --attack-mode=0 --hash-type=0 [hashes file] /mnt/wordlist/wordlist.txt
```

And finally, one small tip: start any cracking attempts in a screen or tmux
session, so if your SSH connection drops, you can reconnect. This is speaking
from experience!

## Conclusion

That's all there is to it! Performance on the Cluster GPU instance is pretty
decent (you can see above, it can perform about 2320.9 million MD5 hashes per
second), and, once set up, easy to use. Sadly, after running two giant
wordlists against the `md5crypt()` hash that I was testing, I didn't have any
luck. And since the instances are a bit pricy for a student to keep running, I
decided to shut it down and earn those 7% the hard way. Back to studying!
Though, if anyone feels like helping me earn those bonus marks, the hash can be
found below.

```
$apr1$LJgyupye$GZQc9jyvrdP50vW77sYvz1
```

An additional note: while convenient, this isn't the world's most efficient way
to do hash cracking. If you have the money, [CloudCracker][cloudcracker] is a
service I've heard good things about - though it doesn't support all the hash
types that oclHashcat does. Also, physical hardware will outperform EC2 pretty
much all the time, so if you really need the extra speed, it would be worth
investing in a few dedicated servers. A good example of something like this can
be found [here][gpucluster].

[cloudcracker]: https://www.cloudcracker.com/
[gpucluster]: http://arstechnica.com/security/2012/12/25-gpu-cluster-cracks-every-standard-windows-password-in-6-hours/
