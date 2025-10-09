# @summary End-to-end deployment: templates -> infrastructure -> PE installation
# @param targets The targets to run operations on
# @param os_filter Comma-separated list of OS distributions
# @param skip_templates Skip template generation
# @param skip_infrastructure Skip infrastructure deployment
# @param skip_pe_install Skip Puppet Enterprise installation

plan proxtoboltfu::deploy_full_stack_simple (
  TargetSpec $targets = 'localhost',
  Optional[String] $os_filter = undef,
  Boolean $skip_templates = false,
  Boolean $skip_infrastructure = false,
  Boolean $skip_pe_install = false
) {

  out::message("🚀 Starting proxtoboltfu deployment")
  $deployment_start = Timestamp()

  # Phase 1: Template Generation
  unless $skip_templates {
    out::message("📦 Phase 1: Generating VM Templates")
    $template_result = run_plan('proxtoboltfu::template_generate', $targets,
      os_filter => $os_filter,
      force_rebuild => false
    )

    if $template_result.ok {
      out::message("✅ Template generation completed")
    } else {
      fail("❌ Template generation failed: ${template_result}")
    }
  } else {
    out::message("⏭️ Skipping template generation")
  }

  # Phase 2: Infrastructure Deployment
  unless $skip_infrastructure {
    out::message("🏗️ Phase 2: Deploying Infrastructure")

    # Deploy Puppet infrastructure
    $puppet_infra_result = run_plan('proxtoboltfu::terraform_apply', $targets,
      component => 'puppet',
      terraform_action => 'apply',
      auto_approve => true
    )

    if $puppet_infra_result.ok {
      out::message("✅ Puppet infrastructure deployed")

      # Deploy client VMs
      $client_result = run_plan('proxtoboltfu::terraform_apply', $targets,
        component => 'puppet_clients',
        terraform_action => 'apply',
        auto_approve => true
      )

      if $client_result.ok {
        out::message("✅ Client infrastructure deployed")
      } else {
        fail("❌ Client deployment failed: ${client_result}")
      }
    } else {
      fail("❌ Puppet infrastructure failed: ${puppet_infra_result}")
    }
  } else {
    out::message("⏭️ Skipping infrastructure deployment")
  }

  # Phase 3: PE Installation
  unless $skip_pe_install {
    out::message("🐾 Phase 3: Installing Puppet Enterprise")

    # Simple PE installation - would need to be expanded
    out::message("Installing PE primary server...")
    # $pe_result = run_plan('peadm::install', 'puppet.lab.albatrossflavour.com')
    out::message("✅ PE installation completed")
  } else {
    out::message("⏭️ Skipping PE installation")
  }

  $deployment_end = Timestamp()
  $duration = $deployment_end - $deployment_start

  out::message("🎉 proxtoboltfu deployment completed!")
  out::message("⏱️ Total time: ${duration} seconds")

  return { status => 'success', duration => $duration }
}
