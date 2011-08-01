require 'spec_helper'

describe Emailer do
  context "notify_conversation" do
    before do
      @conversation = Factory(:conversation)
      @user = @conversation.user
      @project = @conversation.project
      @address = %(#{@project.permalink}+conversation+#{@conversation.id}@domain.com)
      @full_address = %(#{@user.name} <#{@address}>)
    end
  
    it "should set Reply-to" do
      allow_incoming_mail do
        email = Emailer.notify_conversation(@user.id, @conversation.project.id, @conversation.id)
        email[:from].decoded.should == @full_address
        email.reply_to.should == [@address]
      end
    end
  
    it "should not set Reply-to for no-reply" do
      allow_incoming_mail(false) do
        email = Emailer.notify_conversation(@user.id, @conversation.project.id, @conversation.id)
        email.from.should == ['no-reply@domain.com']
        email.reply_to.should be_nil
      end
    end
  end

  describe "email headers and titles for threading" do
    before do
      I18n.locale = :en
      @user = Factory(:user, :locale => I18n.locale.to_s)
      @another_user = Factory(:user, :locale => I18n.locale.to_s)
      @email_domain = Teambox.config.smtp_settings.domain
      @task = Factory(:task)
      @project = @task.project
      @first_comment = Factory(:comment, :target => @task)
      @conversation = Factory(:conversation)
    end

    it "should set correct header and title for task notification" do
      @email = Emailer.notify_task(@user.id, @project.id, @task.id)
      @email.subject.should eql "[#{@project.permalink}] #{@task.name}"
      @email.message_id.should eql "project_#{@project.id}/task_#{@task.id}/comment_#{@first_comment.id}@#{@email_domain}"
      @email.in_reply_to.should be nil
    end

    it "should set correct header and title for task second comment notification" do
      @second_comment = Factory(:comment, :target => @task, :project => @project, :user => @another_user,
        :body => "I agree!", :created_at => @first_comment.created_at + 5.minutes )
      @second_email = Emailer.notify_task(@user.id, @project.id, @task.id)
      @second_email.subject.should eql "Re: [#{@project.permalink}] #{@task.name}"
      @second_email.message_id.should eql "project_#{@project.id}/task_#{@task.id}/comment_#{@second_comment.id}@#{@email_domain}"
      @second_email.in_reply_to.should eql "project_#{@project.id}/task_#{@task.id}/comment_#{@first_comment.id}@#{@email_domain}"
    end

    it "should set correct header and title for conversation notification" do
      @email = Emailer.notify_conversation(@user.id, @project.id, @conversation.id)
      @email.subject.should eql "[#{@project.permalink}] #{@conversation.name}"
      @email.message_id.should eql "project_#{@project.id}/conversation_#{@conversation.id}/comment_#{@conversation.first_comment.id}@#{@email_domain}"
      @email.in_reply_to.should be nil
    end

    it "should set correct header and title for conversation second comment notification" do
      @second_comment = Factory(:comment, :target => @conversation, :user => @another_user, :project => @project,
        :body => "Disagree!", :created_at => @conversation.first_comment.created_at + 5.minutes )
      @second_email = Emailer.notify_conversation(@user.id, @project.id, @conversation.id)
      @second_email.subject.should eql "Re: [#{@project.permalink}] #{@conversation.name}"
      @second_email.message_id.should eql "project_#{@project.id}/conversation_#{@conversation.id}/comment_#{@second_comment.id}@#{@email_domain}"
      @second_email.in_reply_to.should eql "project_#{@project.id}/conversation_#{@conversation.id}/comment_#{@conversation.first_comment.id}@#{@email_domain}"
    end

  end

  describe "email rendering" do
    # I18n.available_locales, too slow! Top 3 only
    [:en, :es, :fr].each do |locale|
      before do
        @user = Factory(:user, :locale => locale.to_s)
      end

      it "should render valid task notification for #{locale}" do
        @task = Factory(:task)
        Factory(:comment, :target => @task, :project => @task.project, :user => @task.user)

        with_locale(locale) do
          lambda { Emailer.notify_task(@user.id, @task.project.id, @task.id) }.should_not raise_error
        end

      end

      it "should render valid conversation notification for #{locale}" do
        @conversation = Factory(:conversation)
        Factory(:comment, :target => @conversation, :project => @conversation.project, :user => @conversation.user)

        with_locale(locale) do
          lambda { Emailer.notify_conversation(@user.id, @conversation.project.id, @conversation.id) }.should_not raise_error
        end
      end

      it "should render valid daily task reminder for #{locale}" do
        @task = Factory(:task)
        @task.assign_to(@user)
        @task.save

        Factory(:comment, :target => @task, :due_on => Time.now + 1.day, :project => @task.project, :user => @task.user)

        with_locale(locale) do
          lambda { Emailer.daily_task_reminder(@user.id) }.should_not raise_error
        end
      end

      it "should render valid signup invitation for #{locale}" do
        @invitation = Factory(:invitation)

        with_locale(locale) do
          lambda { Emailer.signup_invitation(@invitation.id) }.should_not raise_error
        end
      end

      it "should render valid reset password for #{locale}" do
        with_locale(locale) do
          lambda { Emailer.reset_password(@user.id) }.should_not raise_error
        end
      end

      it "should render valid forgot password for #{locale}" do
        @password_reset = Factory(:reset_password)

        with_locale(locale) do
          lambda { Emailer.forgot_password(@password_reset.id) }.should_not raise_error
        end
      end

      it "should render valid project membership notification for #{locale}" do
        @invitation = Factory(:invitation)
        @invitation.invited_user = Factory(:user)
        @invitation.save

        with_locale(locale) do
          lambda { Emailer.project_membership_notification(@invitation.id) }.should_not raise_error
        end
      end

      it "should render valid project invitation for #{locale}" do
        @invitation = Factory(:invitation)
        with_locale(locale) do
          lambda { Emailer.project_invitation(@invitation.id) }.should_not raise_error
        end
      end

      it "should render valid email confirmation for #{locale}" do
        with_locale(locale) do
          lambda { Emailer.confirm_email(@user.id) }.should_not raise_error
        end
      end

      it "should render valid public download for #{locale}" do
        @upload = Factory(:upload)

        with_locale(locale) do
          lambda { Emailer.public_download(@upload.id) }.should_not raise_error
        end
      end

    end
  end

  def with_locale(language)
    old_locale = I18n.locale
    I18n.locale = language
    yield
    I18n.locale = old_locale
  end

  def allow_incoming_mail(really = true)
    old_value = Teambox.config.allow_incoming_email
    Teambox.config.allow_incoming_email = really
    begin
      yield
    ensure
      Teambox.config.allow_incoming_email = old_value
    end
  end
end
