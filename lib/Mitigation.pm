# SUSE's openQA tests
#
# Copyright © 2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Mitigation testcase library provides a class to execute
# common test steps. Specificaly checkpoint could be done in individual
# test module via override functions in this class, or extend the test.
#
# Usage, when you need to testing a mitigation function.
# you need to initialize a hash struct seems like:
#
#my %mitigations_list =
#  (
#    name                   => "l1tf",
#    CPUID                  => hex '10000000',
#    IA32_ARCH_CAPABILITIES => 8,                #bit3 --SKIP_L1TF_VMENTRY
#    parameter              => 'l1tf',
#    cpuflags               => ['flush_l1d'],
#    sysfs_name             => "l1tf",
#    sysfs                  => {
#        "full"         => "Mitigation: PTE Inversion; VMX: cache flushes, SMT disabled",
#        "full,force"   => "Mitigation: PTE Inversion; VMX: cache flushes, SMT disabled",
#        "flush"        => "Mitigation: PTE Inversion; VMX: conditional cache flushes, SMT vulnerable",
#        "flush,nosmt"  => "Mitigation: PTE Inversion; VMX: conditional cache flushes, SMT disabled",
#        "flush,nowarn" => "Mitigation: PTE Inversion; VMX: conditional cache flushes, SMT vulnerable",
#        "off"          => "Mitigation: PTE Inversion; VMX: vulnerable",
#        "default"      => "Mitigation: PTE Inversion; VMX: conditional cache flushes, SMT vulnerable",
#    },
#    cmdline => [
#        "full",
#        "full,force",
#        "flush",
#        "flush,nosmt",
#        "flush,nowarn",
#        "off",
#    ],
#  );
#
#  "name", the name of test module or mitigations name.
#  "CPUID", the bit that should be check via cpuid instruction. follow Intel manual.
#  "IA32_ARCH_CAPABILITIES", the bit that means this mitigations might be fixed by Hardware.
#  "parameter", the name of parameter on kernel cmdline, as switch to enable or disable this mitigation in system.
#  "cpuflags", the flag[s] name should be appear at /proc/cpuinfo or lscpu.
#  "sysfs_name", the name of entry in sysfs: /sys/devices/system/cpu/vulnerabilities/*,
#  "sysfs", a hash with  {"name" => "string"}
#  	Means, when "name" be used as a kernel parameter to value, the "string" should be the context of "sysfs_name".
#  "cmdline", an array that store what kernel parameter will be tested.
#
## Maintainer: James Wang <jnwang@suse.com>
#
package Mitigation;
use strict;
use warnings;
use base "consoletest";
use testapi;
use utils;
use Utils::Backends 'use_ssh_serial_console';
use bootloader_setup qw(grub_mkconfig change_grub_config add_grub_cmdline_settings remove_grub_cmdline_settings grep_grub_settings set_framebuffer_resolution set_extrabootparams_grub_conf);
use ipmi_backend_utils;
use power_action_utils 'power_action';

my $vm_ip_addr;
my $qa_password;

=head2 reboot_and_wait

	reboot_and_wait([timeout => $timeout]);

To reboot and waiting system back and login it.
This could support IPMI and QEMU backend.
C<$timeout> in seconds.
=cut
sub reboot_and_wait {
    my ($self, $timeout) = @_;
    if (check_var('BACKEND', 'ipmi')) {
        power_action('reboot', textmode => 1, keepconsole => 1);
        switch_from_ssh_to_sol_console(reset_console_flag => 'on');
        check_screen([qw(login_screen linux-login)], $timeout);
        use_ssh_serial_console;

    }
    else {
        power_action('reboot', textmode => 1);
        $self->wait_boot(textmode => 1, ready_time => 300, in_grub => 1);
        select_console 'root-console';
    }
}

our $syspath = '/sys/devices/system/cpu/vulnerabilities/';

#If you base on this Class, you have to override new function,
#so that it could be loaded by openQA.
#
sub new {
    my ($class, $args) = @_;
    if (ref($args)) {
        return bless $args, $class;
    }
    else {
        my $self = $class->SUPER::new($args);
        return bless $self, $class;
    }
}

sub Parameter {
    my ($self, $value) = @_;
    if (@_ == 2) {
        $self->{parameter} = $value;
    }
    return $self->{Parameter};
}
sub sysfs_name {
    my ($self, $value) = @_;
    if (@_ == 2) {
        $self->{sysfs_name} = $value;

    }
    return $self->{sysfs_name};
}
sub CPUID {
    my $self = shift;
    return $self->{CPUID};
}

sub MSR {
    my $self = shift;
    return $self->{IA32_ARCH_CAPABILITIES};
}

sub read_cpuid {
    my $self = shift;
    zypper_call('in cpuid');
    my $edx = hex script_output(
        "cpuid -1 -l 7 -s 0 -r | awk \'{print \$6}\' | awk -F \"=\" \'{print \$2}\' | tail -n1"
    );
    return $edx;
}

sub read_msr {
    my $self = shift;
    script_output('modprobe msr');
    my $edx = script_output(
        "perl -e \'open(M,\"<\",\"/dev/cpu/0/msr\") and seek(M,0x10a,0) and read(M,\$_,8) and print\' | od -t u8 -A n"
    );
    return $edx;
}

sub vulnerabilities {
    my $self = shift;
    if ($self->read_cpuid() & $self->CPUID()) {
        if ($self->read_msr() & $self->MSR()) {
            record_info("Not Affected", "This machine needn't be tested.");
            return 0;    #Not Affected
        }
    }
    record_info("vulnerable", "Testing will continue.");
    return 1;            #Affected
}

sub sysfs {
    my ($self, $value) = @_;
    $value =~ s/,/_/g;
    if (@_ == 2) {
        return $self->{sysfs}->{$value};
    }
    return $self->{sysfs};

}

sub dmesg {
    my $self = shift;
    for my $p (keys %{$self->{dmesg}}) {
        print "dmesg " . $self->Name . "\n";
        print $self->{dmesg}->{$p} . "\n";
    }
}

sub cmdline {
    my $self = shift;
    return $self->{cmdline};
}

sub lscpu {
    my $self = shift;
    for my $p (keys %{$self->{lscpu}}) {
        print $p. "\n";
    }
}



#This function will finish testing in default status.
#As out of box testing. and clean up all mitigations parameters.
sub check_default_status {
    my $self = shift;
    assert_script_run('cat /proc/cmdline');
    my $ret = script_run('grep "' . $self->{parameter} . '=[a-z,]*" /proc/cmdline');
    if ($ret eq 0) {
        remove_grub_cmdline_settings($self->{parameter} . "=[a-z,]*");
    }
    $ret = script_run('grep "' . "mitigations" . '=[a-z]*" /proc/cmdline');
    if ($ret eq 0) {
        remove_grub_cmdline_settings("mitigations=[a-z]*");
    }
    reboot_and_wait($self, 150);
    $ret = script_run('grep "' . $self->{parameter} . '=off" /proc/cmdline');
    if ($ret eq 0) {
        die "there are still have parameter will impacted our test";
    }
}

#Check cpu flags exist or not.
#when $cmd is off, the match is inverted.
sub check_cpu_flags {
    my ($self) = @_;
    assert_script_run('cat /proc/cpuinfo');
    foreach my $flag (@{$self->{cpuflags}}) {
        my $ret = script_run('cat /proc/cpuinfo | grep "^flags.*' . $flag . '.*"');
        if (get_var('MACHINE', '') =~ /NO-IBRS$/ && check_var('BACKEND', 'qemu')) {
            if ($ret ne 0) {
                record_info("NOT PASSTHROUGH", "Host didn't pass flags into this VM.");
                return;
            } else {
                die "VM didn't bring CPU flags";
            }
        }
    }
}

sub check_sysfs {
    my ($self, $value) = @_;
    assert_script_run('cat ' . $syspath . $self->sysfs_name());
    if (@_ == 2) {
        assert_script_run(
            'cat ' . $syspath . $self->sysfs_name() . '| grep ' . '"' . $self->sysfs($value) . '"');
    }
}

sub check_dmesg {
    my ($self, $value) = @_;    #the value of kernel parameter
    $value =~ s/,/_/g;
    foreach my $string ($self->{dmesg}->{$value}) {
        assert_script_run(
            'dmesg | grep "' . $string . '"');
    }
}

sub check_cmdline {
    my $self = shift;
    assert_script_run(
        'cat /proc/cmdline'
    );

}

#check only one cmdline item.
sub check_one_parameter_value {
    #testing one parameter.
    my ($self, $cmd) = @_;
    if ($cmd) {
        $self->add_parameter($cmd);
        $self->check_cpu_flags($cmd);
        $self->check_sysfs($cmd);
        $self->remove_parameter($cmd);
    }
}


#check all cmdline items.
sub check_each_parameter_value {
    #testing each parameter.
    my $self = shift;
    foreach my $cmd (@{$self->cmdline()}) {
        record_info("$self->{name}=$cmd", "Mitigation $self->{name} = $cmd  testing start.");
        $self->add_parameter($cmd);
        $self->check_cmdline();
        $self->check_cpu_flags($cmd);
        $self->check_cmdline();
        $self->check_sysfs($cmd);
        $self->remove_parameter($cmd);
    }
}


sub add_parameter {
    my ($self, $value) = @_;
    add_grub_cmdline_settings($self->{parameter} . '=' . $value);
    grub_mkconfig();
    reboot_and_wait($self, 150);
}

sub remove_parameter {
    my ($self, $value) = @_;
    remove_grub_cmdline_settings($self->{parameter} . '=' . $value);
}

sub ssh_vm_cmd {
    my ($cmd, $qa_password, $vm_ip_addr) = @_;
    my $ret = script_run("sshpass -p ${qa_password} ssh -qy root\@${vm_ip_addr} $cmd");
    return $ret;
}

sub mds_taa_check {
    my ($qa_password, $mdstaa_domain_name, $vm_ip_addr) = @_;
    #mds=off and taa=off need to be tested in the same time
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"\\\"/GRUB_CMDLINE_LINUX=\\\"mds=off\\ tsx_async_abort=off\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $mdstaa_domain_name, $vm_ip_addr);
    my $ret = ssh_vm_cmd("cat /sys/devices/system/cpu/vulnerabilities/mds | grep \"Vulnerable; SMT Host state unknown\"", $qa_password, $vm_ip_addr);
    if ($ret ne 0) {
        record_info('ERROR', "hvm_mds=off test is failed.", result => 'fail');
    }
    record_info('INFO', "hvm_mds=off test is finished.");
    $ret = ssh_vm_cmd("cat /sys/devices/system/cpu/vulnerabilities/tsx_async_abort | grep \"Vulnerable\"", $qa_password, $vm_ip_addr);
    if ($ret ne 0) {
        record_info('ERROR', "hvm_taa=off test is failed.", result => 'fail');
    }
    record_info('INFO', "hvm_taa=off test is finished.");
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"mds=off\\ tsx_async_abort=off\\\"/GRUB_CMDLINE_LINUX=\\\"\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $mdstaa_domain_name, $vm_ip_addr);
}

sub config_and_reboot {
    my ($qa_password, $vm_domain_name, $vm_ip_addr) = @_;
    my $config_ret = ssh_vm_cmd("grub2-mkconfig -o /boot/grub2/grub.cfg", $qa_password, $vm_ip_addr);
    if ($config_ret ne 0) {
        ssh_vm_cmd("grub2-mkconfig -o /boot/grub2/grub.cfg", $qa_password, $vm_ip_addr);
    }
    record_info('INFO', "Config success.");
    ssh_vm_cmd("poweroff", $qa_password, $vm_ip_addr);
    script_run('virsh list --all');
    script_run("virsh start \"${vm_domain_name}\"");
    script_run('echo Now I am waiting for the vm to reboot');
    script_run("sleep 60");
    ssh_vm_cmd("cat /proc/cmdline", $qa_password, $vm_ip_addr);
}

sub do_check {
    my ($secnario, $qa_password, $dc_domain_name, $vm_ip_addr) = @_;
    my $foo = $secnario->{default};
    if ($foo->{expected}) {
        while (my ($cmd, $lines) = each %{$foo->{expected}}) {
            foreach my $expected_string (@{$lines}) {
                if ($expected_string ne "") {
                    ssh_vm_cmd("$cmd", $qa_password, $vm_ip_addr);
                    my $ret = ssh_vm_cmd("$cmd | grep \"$expected_string\"", $qa_password, $vm_ip_addr);
                    record_info("ERROR", "Can't found a expected string.", result => 'fail') unless $ret eq 0;
                } else {
                    print "This expection is empty string, skip";
                }

            }
        }
    }
    if ($foo->{unexpected}) {
        while (my ($cmd, $lines) = each %{$foo->{unexpected}}) {
            foreach my $unexpected_string (@{$lines}) {
                if ($unexpected_string ne "") {
                    my $ret = ssh_vm_cmd("$cmd | grep \"$unexpected_string\"", $qa_password, $vm_ip_addr);
                    record_info("ERROR", "found a unexpected string.", result => 'fail') unless $ret ne 0;
                } else {
                    #Debug what output be report.
                    assert_script_run("xl dmesg | grep -A 10 \"Speculative\"");
                    print "This unexpection is empty string, skip";
                }

            }
        }
    }
}

sub pti_check {
    my ($qa_password, $pti_domain_name, $vm_ip_addr) = @_;
    #pti test need to be conducted separately
    my $check_para;
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"\\\"/GRUB_CMDLINE_LINUX=\\\"pti=on\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $pti_domain_name, $vm_ip_addr);
    if ($pti_domain_name eq 'pv_worker') {
        $check_para = "Unknown (XEN PV detected, hypervisor mitigation required)";
    }
    if ($pti_domain_name eq 'hvm_worker') {
        $check_para = "Mitigation: PTI";
    }
    my $ret = ssh_vm_cmd("cat /sys/devices/system/cpu/vulnerabilities/meltdown | grep \"$check_para\"", $qa_password, $vm_ip_addr);
    if ($ret ne 0) {
        record_info('ERROR', "$pti_domain_name pti=on test is failed.", result => 'fail');
    }
    record_info('INFO', "$pti_domain_name pti=on test is finished.");
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"pti=on\\\"/GRUB_CMDLINE_LINUX=\\\"\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $pti_domain_name, $vm_ip_addr);
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"\\\"/GRUB_CMDLINE_LINUX=\\\"pti=auto\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $pti_domain_name, $vm_ip_addr);
    $ret = ssh_vm_cmd("cat /sys/devices/system/cpu/vulnerabilities/meltdown | grep \"$check_para\"", $qa_password, $vm_ip_addr);
    if ($ret ne 0) {
        record_info('ERROR', "$pti_domain_name pti=auto test is failed.", result => 'fail');
    }
    record_info('INFO', "$pti_domain_name pti=auto test is finished.");
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"pti=auto\\\"/GRUB_CMDLINE_LINUX=\\\"\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $pti_domain_name, $vm_ip_addr);
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"\\\"/GRUB_CMDLINE_LINUX=\\\"pti=off\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $pti_domain_name, $vm_ip_addr);
    if ($pti_domain_name eq 'hvm_worker') {
        $check_para = "Vulnerable";
    }
    $ret = ssh_vm_cmd("cat /sys/devices/system/cpu/vulnerabilities/meltdown | grep \"$check_para\"", $qa_password, $vm_ip_addr);
    if ($ret ne 0) {
        record_info('ERROR', "$pti_domain_name pti=off test is failed.", result => 'fail');
    }
    record_info('INFO', "$pti_domain_name pti=off test is finished.");
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"pti=off\\\"/GRUB_CMDLINE_LINUX=\\\"\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $pti_domain_name, $vm_ip_addr);
}

sub cycle_workflow {
    my ($self, $carg, $ckey, $cvalue, $qa_password, $cvm_domain_name, $vm_ip_addr, $pv_hypsecnario) = @_;
    my $parameter = $carg . '=' . $ckey;
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"\\\"/GRUB_CMDLINE_LINUX=\\\"$parameter\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    my $cmd_ret = ssh_vm_cmd("cat /etc/default/grub | grep \"$parameter\"", $qa_password, $vm_ip_addr);
    if ($cmd_ret ne 0) {
        ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"\\\"/GRUB_CMDLINE_LINUX=\\\"$parameter\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    }
    config_and_reboot($qa_password, $cvm_domain_name, $vm_ip_addr);
    my $ret = do_check($cvalue, $qa_password, $cvm_domain_name, $vm_ip_addr, $pv_hypsecnario);
    if ($ret ne 0) {
        record_info('ERROR', "$parameter test is failed.", result => 'fail');
    }
    record_info('INFO', "$parameter test is finished.");
    ssh_vm_cmd("sed -i -e 's/GRUB_CMDLINE_LINUX=\\\"$parameter\\\"/GRUB_CMDLINE_LINUX=\\\"\\\"/' /etc/default/grub", $qa_password, $vm_ip_addr);
    config_and_reboot($qa_password, $cvm_domain_name, $vm_ip_addr);
}

sub guest_cycle {
    my ($self, $hash, $single, $mode, $qa_password, $gcvm_domain_name, $vm_ip_addr, $pv_hypsecnario) = @_;
    while (my ($arg, $dict) = each %$hash) {
        if ($mode eq 'single') {
            if ($arg eq $single) {
                while (my ($key, $value) = each %$dict) {
                    cycle_workflow($self, $arg, $key, $value, $qa_password, $gcvm_domain_name, $vm_ip_addr, $pv_hypsecnario);
                }
            }
        }
        if ($mode eq 'all') {
            while (my ($key, $value) = each %$dict) {
                cycle_workflow($self, $arg, $key, $value, $qa_password, $gcvm_domain_name, $vm_ip_addr, $pv_hypsecnario);
            }
        }
    }
}
#This is entry for testing.
#The instances call this function to finish all 'basic' testing.
#This function will check if current machine has a hardware fix.
#If the current machine is not affected, test over.
sub do_test {
    my $self = shift;
    select_console 'root-console';

    #If it is qemu vm and didn't passthrough cpu flags
    #Meltdown doesn't matter CPU flags
    if (get_var('MACHINE') =~ /^qemu-.*-NO-IBRS$/ && check_var('BACKEND', 'qemu') && !(get_var('TEST') =~ /MELTDOWN/)) {
        record_info('NO-IBRS machine', "This is a QEMU VM and didn't passthrough CPU flags.");
        record_info('INFO',            "Check status of mitigations as like OFF.");
        $self->check_sysfs("off");
        return;
    }

    my $ret = $self->vulnerabilities();
    if ($ret == 0) {
        record_info('INFO', "This CPU is not affected by $self->{name}.");
        return 2;
    } else {
        record_info('INFO', "Mitigation $self->{name} testing start.");
    }
    #check system default status
    #and prepare the command line parameter for next testings
    $self->check_default_status();
    $self->check_cpu_flags();
    $self->check_sysfs("default");
    $self->check_each_parameter_value();

    remove_grub_cmdline_settings($self->{parameter} . '=' . '[a-z,]*');
}

# Initialize junit xml file structure.
sub init_xml {
    my %args = {
        testsuites_name => 'ts',
        file_name       => '/tmp/junit.xml'
    };
    %args = @_;
    my $xml_content = << "EOF";
<testsuites error='0' failures='0' name=\\"$args{testsuites_name}\\" skipped='0' tests='0' time=''>
</testsuites>
EOF
    assert_script_run("echo \"$xml_content\" > $args{file_name}", 200);

}

sub append_ts2_xml {
    my %args = {
        testsuite_name => 'ts',
        file_name      => '/tmp/junit.xml'
    };
    %args = @_;
    my $cmd_append_ts2_xml = << "EOF";
xmlstarlet ed  -P -L -s /testsuites -t elem -n testsuite -v '' \\
-i "/testsuites/testsuite[last()]" -t attr -n error -v 0 \\
-i "/testsuites/testsuite[last()]" -t attr -n failures -v 0 \\
-i "/testsuites/testsuite[last()]" -t attr -n hostname -v "`hostname`" \\
-i "/testsuites/testsuite[last()]" -t attr -n id -v '' \\
-i "/testsuites/testsuite[last()]" -t attr -n name -v \"$args{testsuite_name}\" \\
-i "/testsuites/testsuite[last()]" -t attr -n package -v \"$args{testsuite_name}\" \\
-i "/testsuites/testsuite[last()]" -t attr -n  skipped -v 0 \\
-i "/testsuites/testsuite[last()]" -t attr -n tests -v 0 \\
-i "/testsuites/testsuite[last()]" -t attr -n time -v '' \\
-i "/testsuites/testsuite[last()]" -t attr -n timestamp -v "`date +%Y-%m-%dT%X`" $args{file_name} \\
EOF
    assert_script_run($cmd_append_ts2_xml, 200);
}

# Update testsuites atturate value
sub update_tss_attr {
    my %args = {
        file_name => "/tmp/junit.xml",
        attr      => 0,
        value     => 0
    };
    %args = @_;
    my $cmd_update_tss_attr = << "EOF";
xmlstarlet ed -L -u /testsuites/\@$args{attr} -v $args{value}  $args{file_name} \\
EOF
    assert_script_run($cmd_update_tss_attr, 200);
}

# update testsuite atturate
sub update_ts_attr {
    my %args = {
        file_name   => "/tmp/junit.xml",
        ts_position => -1,
        attr        => 0,
        value       => 0
    };
    %args = @_;
    my $cmd_update_ts_attr = << "EOF";
xmlstarlet ed -L -u "/testsuites/testsuite[last()]/\@$args{attr}" -v $args{value}  $args{file_name} \\
EOF
    assert_script_run($cmd_update_ts_attr, 200);
}

# Insert one test case to existing junit file
sub insert_tc2_xml {
    my %args = {
        file_name   => "/tmp/junit.xml",
        class_name  => '',
        case_status => 'pass',
        sys_output  => '',
        sys_err     => ''
    };
    %args = @_;
    my $cmd_insert_tc2_xml = << "EOF";
xmlstarlet ed  -L -s "/testsuites/testsuite[last()]" -t elem -n testcase -v "" \\
-s "/testsuites/testsuite[last()]/testcase[last()]" -t elem -n system-err -v "$args{sys_err}" \\
-s "/testsuites/testsuite[last()]/testcase[last()]" -t elem -n system-out -v "$args{sys_output}" \\
-i "/testsuites/testsuite[last()]/testcase[last()]" -t attr -n classname -v "$args{class_name}" \\
-i "/testsuites/testsuite[last()]/testcase[last()]" -t attr -n name -v "$args{class_name}" \\
-i "/testsuites/testsuite[last()]/testcase[last()]" -t attr -n status  -v "$args{case_status}" \\
-i "/testsuites/testsuite[last()]/testcase[last()]" -t attr -n time  -v "none" $args{file_name} \\
EOF

    assert_script_run($cmd_insert_tc2_xml, 200);
}

1;
