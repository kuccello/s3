# encoding: utf-8
require 'test_helper'

class ObjectTest < Test::Unit::TestCase
  def setup
    @service = S3::Service.new(
      :access_key_id => "1234",
      :secret_access_key => "1337"
    )
    @bucket_images = S3::Bucket.send(:new, @service, "images")
    @object_lena = S3::Object.send(:new, @bucket_images, :key => "Lena.png")
    @object_lena.content = "test"
    @object_carmen = S3::Object.send(:new, @bucket_images, :key => "Carmen.png")

    @response_binary = Net::HTTPOK.new("1.1", "200", "OK")
    stub(@response_binary).body { "test".force_encoding(Encoding::BINARY) }
    @response_binary["etag"] = ""
    @response_binary["content-type"] = "image/png"
    @response_binary["content-disposition"] = "inline"
    @response_binary["content-encoding"] = nil
    @response_binary["last-modified"] = Time.now.httpdate
    @response_binary["content-length"] = 20

    @xml_body = <<-EOXML
    <?xml version="1.0" encoding="UTF-8"?>
    <CopyObjectResult> <LastModified>timestamp</LastModified> <ETag>"etag"</ETag> </CopyObjectResult>
    EOXML
    @response_xml = Net::HTTPOK.new("1.1", "200", "OK")
    stub(@response_xml).body { @xml_body }
  end

  def test_initilalize
    assert_raise ArgumentError do S3::Object.send(:new, nil, :key => "") end # should not allow empty key
    assert_raise ArgumentError do S3::Object.send(:new, nil, :key => "//") end # should not allow key with double slash

    assert_nothing_raised do
      S3::Object.send(:new, nil, :key => "Lena.png")
      S3::Object.send(:new, nil, :key => "Lena playboy.png")
      S3::Object.send(:new, nil, :key => "Lena Söderberg.png")
      S3::Object.send(:new, nil, :key => "/images/pictures/test images/Lena not full.png")
    end
  end

  def test_full_key
    expected = "images/Lena.png"
    actual = @object_lena.full_key
    assert_equal expected, actual
  end

  def test_url
    bucket1 = S3::Bucket.send(:new, @service, "images")

    object11 = S3::Object.send(:new, bucket1, :key => "Lena.png")
    expected = "http://images.s3.amazonaws.com/Lena.png"
    actual = object11.url
    assert_equal expected, actual

    object12 = S3::Object.send(:new, bucket1, :key => "Lena Söderberg.png")
    expected = "http://images.s3.amazonaws.com/Lena%20S%C3%B6derberg.png"
    actual = object12.url
    assert_equal expected, actual

    bucket2 = S3::Bucket.send(:new, @service, "images_new")

    object21 = S3::Object.send(:new, bucket2, :key => "Lena.png")
    expected = "http://s3.amazonaws.com/images_new/Lena.png"
    actual = object21.url
    assert_equal expected, actual
  end

  def test_cname_url
    bucket1 = S3::Bucket.send(:new, @service, "images.example.com")

    object11 = S3::Object.send(:new, bucket1, :key => "Lena.png")
    expected = "http://images.example.com/Lena.png"
    actual = object11.cname_url
    assert_equal expected, actual

    object12 = S3::Object.send(:new, bucket1, :key => "Lena Söderberg.png")
    expected = "http://images.example.com/Lena%20S%C3%B6derberg.png"
    actual = object12.cname_url
    assert_equal expected, actual

    bucket2 = S3::Bucket.send(:new, @service, "images_new")

    object21 = S3::Object.send(:new, bucket2, :key => "Lena.png")
    expected = nil
    actual = object21.cname_url
    assert_equal expected, actual
  end

  def test_destroy
    mock(@object_lena).object_request(:delete) {}
    assert @object_lena.destroy
  end

  def test_save
    mock(@object_lena).object_request(:put, :body=>"test", :headers=>{ :x_amz_acl=>"public-read", :content_type=>"application/octet-stream" }) { @response_binary }

    assert @object_lena.save
  end

  def test_content_and_parse_headers
    mock(@object_lena).object_request(:get, {}).times(2) { @response_binary }

    expected = /test/n
    actual = @object_lena.content(true) # wtf? don't work with false, maybe is not fully cleaned
    assert_match expected, actual
    assert_equal "image/png", @object_lena.content_type

    stub(@object_lena).object_request(:get) { flunk "should not use connection" }

    assert @object_lena.content
    assert @object_lena.content(true)
  end

  def test_retrieve
    mock(@object_lena).object_request(:get, :headers=>{:range=>0..0}) { @response_binary }
    assert @object_lena.retrieve
  end

  def test_exists
    mock(@object_lena).retrieve { true }
    assert @object_lena.exists?

    mock(@object_carmen).retrieve { raise S3::Error::NoSuchKey.new(nil, nil) }
    assert ! @object_carmen.exists?
  end

  def test_acl_writer
    expected = nil
    actual = @object_lena.acl
    assert_equal expected, actual

    assert @object_lena.acl = :public_read

    expected = "public-read"
    actual = @object_lena.acl
    assert_equal expected, actual

    assert @object_lena.acl = :private

    expected = "private"
    actual = @object_lena.acl
    assert_equal expected, actual
  end

  def test_copy
    mock(@bucket_images).bucket_request(:put, :path => "Lena-copy.png", :headers => { :x_amz_acl => "public-read", :content_type => "application/octet-stream", :x_amz_copy_source => "images/Lena.png", :x_amz_metadata_directive => "REPLACE" }) { @response_xml }

    new_object = @object_lena.copy(:key => "Lena-copy.png")

    assert_equal "Lena-copy.png", new_object.key
    assert_equal "Lena.png", @object_lena.key
  end
end
