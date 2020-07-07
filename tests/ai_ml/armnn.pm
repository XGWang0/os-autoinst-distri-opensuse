# SUSE's openQA tests
#
# Copyright © 2020 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: This module install armnn and downloads
#   test programs, models, labels and images.
#   Then, it runs models with the images as inputs.
# Maintainer: Guillaume GARDET <guillaume@opensuse.org>

use strict;
use warnings;
use base "consoletest";
use testapi;
use utils;

sub armnn_get_images {
    assert_script_run('mkdir -p armnn/data');
    assert_script_run('cp ~/data/ai_ml/images/{Cat,Dog,shark}.jpg armnn/data/');
}

sub cleanup_model_folder {
    # Save space by cleaning up models folder
    assert_script_run('rm -rf armnn/models');
}

sub armnn_tf_lite_test_prepare {
    # Only the *.tflite files are needed, but more files are in the archives
    assert_script_run('mkdir -p armnn/models');
    assert_script_run('pushd armnn/models');
    assert_script_run('tar xzf ~/data/ai_ml/models/mnasnet_1.3_224_09_07_2018.tgz');
    assert_script_run('mv mnasnet_*/* .');
    # inception_v3_quant.tgz is too big to be stored on github, so download it here
    assert_script_run('wget http://download.tensorflow.org/models/tflite_11_05_08/inception_v3_quant.tgz -O ~/data/ai_ml/models/inception_v3_quant.tgz');
    assert_script_run('tar xzf ~/data/ai_ml/models/inception_v3_quant.tgz');
    assert_script_run('tar xzf ~/data/ai_ml/models/mobilenet_v1_1.0_224_quant.tgz');
    assert_script_run('tar xzf ~/data/ai_ml/models/mobilenet_v2_1.0_224_quant.tgz');
    assert_script_run('popd');
}

sub armnn_tf_lite_test_run {
    my %opts = @_;
    my $backend_opt;
    $backend_opt = "-c $opts{backend}" if $opts{backend};    # Can be CpuRef, CpuAcc, GpuAcc, ...

    assert_script_run("TfLiteInceptionV3Quantized-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
    assert_script_run("TfLiteMnasNet-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
    assert_script_run("TfLiteMobilenetQuantized-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
    assert_script_run("TfLiteMobilenetV2Quantized-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
}

sub armnn_tf_test_prepare {
    assert_script_run('mkdir -p armnn/data');
    # Copy data files from arm-ml-examples-data, used by TfMnist-Armnn
    assert_script_run("cp /usr/share/armnn-mnist/data/t10k-labels-idx1-ubyte armnn/data/t10k-labels.idx1-ubyte");
    assert_script_run("cp /usr/share/armnn-mnist/data/t10k-images-idx3-ubyte armnn/data/t10k-images.idx3-ubyte");

    assert_script_run('mkdir -p armnn/models');
    assert_script_run('pushd armnn/models');
    # Copy model files from arm-ml-examples-data, used by TfMnist-Armnn
    assert_script_run("cp /usr/share/armnn-mnist/model/* ./");
    # inception_v3_2016_08_28_frozen.pb.tar.gz is big, so download it on demand
    assert_script_run('wget https://storage.googleapis.com/download.tensorflow.org/models/inception_v3_2016_08_28_frozen.pb.tar.gz -O ~/data/ai_ml/models/inception_v3_2016_08_28_frozen.pb.tar.gz');
    assert_script_run('tar xzf ~/data/ai_ml/models/inception_v3_2016_08_28_frozen.pb.tar.gz');
    assert_script_run('popd');
}

sub armnn_tf_test_run {
    my %opts = @_;
    my $backend_opt;
    $backend_opt = "-c $opts{backend}" if $opts{backend};    # Can be CpuRef, CpuAcc, GpuAcc, ...

    assert_script_run("TfInceptionV3-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
    assert_script_run("TfMnist-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
}

sub armnn_onnx_test_prepare {
    assert_script_run('mkdir -p armnn/data');
    # Copy data files from arm-ml-examples-data, used by OnnxMnist-Armnn
    assert_script_run("cp /usr/share/armnn-mnist/data/t10k-labels-idx1-ubyte armnn/data/t10k-labels.idx1-ubyte");
    assert_script_run("cp /usr/share/armnn-mnist/data/t10k-images-idx3-ubyte armnn/data/t10k-images.idx3-ubyte");

    assert_script_run('mkdir -p armnn/models');
    assert_script_run('pushd armnn/models');
    assert_script_run('wget https://onnxzoo.blob.core.windows.net/models/opset_8/mnist/mnist.tar.gz -O ~/data/ai_ml/models/mnist.tar.gz');
    assert_script_run("tar xzf ~/data/ai_ml/models/mnist.tar.gz");
    assert_script_run("cp mnist/model.onnx ./mnist_onnx.onnx");
    assert_script_run('wget https://s3.amazonaws.com/onnx-model-zoo/mobilenet/mobilenetv2-1.0/mobilenetv2-1.0.tar.gz -O ~/data/ai_ml/models/mobilenetv2-1.0.tar.gz');
    assert_script_run("tar xzf ~/data/ai_ml/models/mobilenetv2-1.0.tar.gz");
    assert_script_run("cp mobilenetv2-1.0/mobilenetv2-1.0.onnx ./");
    assert_script_run('popd');
}

sub armnn_onnx_test_run {
    my %opts = @_;
    my $backend_opt;
    $backend_opt = "-c $opts{backend}" if $opts{backend};    # Can be CpuRef, CpuAcc, GpuAcc, ...

    assert_script_run("OnnxMnist-Armnn --data-dir=armnn/data --model-dir=armnn/models -i 1 $backend_opt");
    assert_script_run("OnnxMobileNet-Armnn --data-dir=armnn/data --model-dir=armnn/models -i 3 $backend_opt");
}

sub armnn_caffe_test_prepare {
    assert_script_run('mkdir -p armnn/data');
    # Copy data files from arm-ml-examples-data, used by TfMnist-Armnn
    assert_script_run('cp /usr/share/armnn-mnist/data/t10k-labels-idx1-ubyte armnn/data/t10k-labels.idx1-ubyte');
    assert_script_run('cp /usr/share/armnn-mnist/data/t10k-images-idx3-ubyte armnn/data/t10k-images.idx3-ubyte');

    assert_script_run('mkdir -p armnn/models');
    assert_script_run('pushd armnn/models');
    assert_script_run('cp /usr/share/armnn-mnist/model/*.caffemodel ./');
    assert_script_run('popd');
}

sub armnn_caffe_test_run {
    my %opts = @_;
    my $backend_opt;
    $backend_opt = "-c $opts{backend}" if $opts{backend};    # Can be CpuRef, CpuAcc, GpuAcc, ...

    assert_script_run("CaffeMnist-Armnn --data-dir=armnn/data --model-dir=armnn/models $backend_opt");
}

sub run {
    my ($self)         = @_;
    my $armnn_backends = get_var("ARMNN_BACKENDS");          # Comma-separated list of armnn backends to test explicitly. E.g "CpuAcc,GpuAcc"

    $self->select_serial_terminal;
    zypper_call $armnn_backends =~ /GpuAcc/ ? 'in armnn-opencl' : 'in armnn';
    # Install arm-ml-examples-data as required for TF, ONNX and Caffe tests
    zypper_call 'in arm-ml-examples-data';

    select_console 'user-console';

    # Get images used for tests
    armnn_get_images;

    # Test TensorFlow Lite backend
    record_info('TF Lite', "TensorFlow Lite backend");
    armnn_tf_lite_test_prepare;
    # Run with default backend
    armnn_tf_lite_test_run;
    # Run with explicit backend, if requested
    armnn_tf_lite_test_run(backend => $_) for split(/,/, $armnn_backends);
    cleanup_model_folder;

    # Test TensorFlow backend
    record_info('TensorFlow', "TensorFlow backend");
    armnn_tf_test_prepare;
    armnn_tf_test_run;
    armnn_tf_test_run(backend => $_) for split(/,/, $armnn_backends);
    cleanup_model_folder;

    # Test ONNX backend
    record_info('ONNX', "ONNX backend");
    armnn_onnx_test_prepare;
    armnn_onnx_test_run;
    armnn_onnx_test_run(backend => $_) for split(/,/, $armnn_backends);
    cleanup_model_folder;

    # Test Caffe backend
    record_info('Caffe', "Caffe backend");
    armnn_caffe_test_prepare;
    armnn_caffe_test_run;
    armnn_caffe_test_run(backend => $_) for split(/,/, $armnn_backends);
    cleanup_model_folder;
}

1;
