# Security Policy                                                                                                                                                     
                                                                                                                                                                      
  ## Supported Versions                                                                                                                                                 
                                                                                                                                                                      
  | Version | Supported          |
  | ------- | ------------------ |
  | 1.0.x   | ✅ Yes             |
  | < 1.0   | ❌ No              |                                                                                                                                      
   
  ## Reporting a Vulnerability                                                                                                                                          
                                                                                                                                                                      
  If you discover a security vulnerability in Claude in Safari, please report it responsibly.                                                                           
                                                                                                                                                                      
  **Do not open a public GitHub issue for security vulnerabilities.**                                                                                                   
                                                                                                                                                                      
  ### How to Report                                                                                                                                                     
                                                                                                                                                                      
  Use [GitHub Private Vulnerability Reporting](https://github.com/chriscantu/claude-safari-extension/security/advisories/new) to submit a report. This creates a private
   advisory that only maintainers can see.                                                                                                                            
                                                                                                                                                                        
  ### What to Include                                                                                                                                                 

  - Description of the vulnerability
  - Steps to reproduce
  - Affected component (native app, Safari extension, MCP socket server)                                                                                                
  - Impact assessment (what an attacker could do)                                                                                                                       
                                                                                                                                                                        
  ### Response Timeline                                                                                                                                                 
                                                                                                                                                                      
  - **Acknowledgment**: within 48 hours                                                                                                                                 
  - **Initial assessment**: within 7 days                                                                                                                             
  - **Fix or mitigation**: best effort, depends on severity                                                                                                             
                                                                                                                                                                        
  ### Scope
                                                                                                                                                                        
  The following components are in scope:                                                                                                                                
   
  - **Safari Web Extension** — content scripts, background page, tool handlers                                                                                          
  - **Native macOS App** — MCP socket server, file access, screenshot capture                                                                                         
  - **IPC bridge** — native messaging between the app and extension                                                                                                     
  - **Unix domain socket** — MCP transport layer                                                                                                                        
                                                                                                                                                                        
  ### Out of Scope                                                                                                                                                      
                                                                                                                                                                        
  - Vulnerabilities in Safari itself (report to Apple)                                                                                                                  
  - Vulnerabilities in Claude Code CLI (report to [Anthropic](https://anthropic.com))
  - Issues requiring physical access to an already-authenticated machine                                                                                                
                                                                                                                                                                        
  ## Security Architecture                                                                                                                                              
                                                                                                                                                                        
  Claude in Safari runs with the following security boundaries:                                                                                                         
                                                                                                                                                                      
  - **App Sandbox** enabled — file access restricted to security-scoped bookmarks                                                                                       
  - **MCP socket** scoped to the App Group container, not world-readable                                                                                              
  - **No remote network access** from the native app — all communication is local (CLI → Unix socket → extension)                                                       
  - **Screen Recording** and **Accessibility** permissions are requested explicitly and required only for specific tools 
